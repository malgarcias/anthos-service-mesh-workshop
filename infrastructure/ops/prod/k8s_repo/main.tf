# Copyright 2019 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

locals {
  # Create a folder structure for k8s manifests
  # Copy istio-system namespace and CRDs into each GKE cluster folder
  create_k8s_repo_script = <<EOT
mkdir -p tmp
gsutil cp gs://${var.tfadmin_proj}/ops/k8s/cloudbuild.yaml tmp/cloudbuild.yaml
mkdir -p tmp/"${data.terraform_remote_state.ops_gke.outputs.ops_gke_1_name}"
mkdir -p tmp/"${data.terraform_remote_state.ops_gke.outputs.ops_gke_2_name}"
mkdir -p tmp/"${data.terraform_remote_state.app1_gke.outputs.dev1_gke_1_name}"
mkdir -p tmp/"${data.terraform_remote_state.app1_gke.outputs.dev1_gke_2_name}"
mkdir -p tmp/"${data.terraform_remote_state.app2_gke.outputs.dev2_gke_3_name}"
mkdir -p tmp/"${data.terraform_remote_state.app2_gke.outputs.dev2_gke_4_name}"

gsutil -m cp -r gs://${var.tfadmin_proj}/ops/istio-operator-${var.istio_version}.yaml .
echo $(ls -d tmp/*/) | xargs -n 1 cp istio-operator-${var.istio_version}.yaml

kubectl create namespace istio-system --dry-run -o yaml | tee 01_namespace.yaml
echo $(ls -d tmp/*/) | xargs -n 1 cp 01_namespace.yaml

gsutil cp -r gs://${var.tfadmin_proj}/ops/istiocerts .
kubectl create secret generic -n istio-system \
--from-file=istiocerts/ca-cert.pem \
--from-file=istiocerts/ca-key.pem \
--from-file=istiocerts/root-cert.pem \
--from-file=istiocerts/cert-chain.pem \
--dry-run cacerts -oyaml > 02_istio-cacerts.yaml
echo $(ls -d tmp/*/) | xargs -n 1 cp 02_istio-cacerts.yaml

cat - | tee tmp/README.md << EOF
This is where the k8s manifests live.
EOF
  EOT

  # Add files to repo
  initial_commit_script = <<EOT
git config --global user.email $(gcloud auth list --filter=status:ACTIVE --format='value(account)')
git config --global user.name "terraform"
git config --global credential.'https://source.developers.google.com'.helper gcloud.sh
gcloud source repos clone ${data.terraform_remote_state.cloudbuild.outputs.k8s_repo_name} --project=${data.terraform_remote_state.ops_project.outputs.ops_project_id}
cp -r tmp/. ${data.terraform_remote_state.cloudbuild.outputs.k8s_repo_name}
cd ${data.terraform_remote_state.cloudbuild.outputs.k8s_repo_name}
git add . && git commit -am "cloudbuild"
git push -u origin master
  EOT
}

resource "null_resource" "exec_create_k8s_repo" {
  provisioner "local-exec" {
    interpreter = ["bash", "-exc"]
    command     = local.create_k8s_repo_script
  }

  triggers = {
    script = local.create_k8s_repo_script
  }
}

resource "null_resource" "exec_initial_commit_k8s_repo" {
  provisioner "local-exec" {
    interpreter = ["bash", "-exc"]
    command = local.initial_commit_script
  }
  depends_on=[null_resource.exec_create_k8s_repo,]

  triggers = {
    script        = local.initial_commit_script
    repo_contents = local.create_k8s_repo_script
  }
}
