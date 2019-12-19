# create dev1 project
module "create_dev1_project" {
  source                  = "terraform-google-modules/project-factory/google"
  version                 = "4.0.1"
  billing_account         = "${var.billing_account}"
  name                    = "${var.dev1_project_name}"
  default_service_account = "keep"
  org_id                  = "${var.org_id}"
  folder_id               = data.terraform_remote_state.host_project.outputs.folder_name
  shared_vpc              = data.terraform_remote_state.shared_vpc.outputs.svpc_host_project_id
  shared_vpc_subnets = [
    "projects/${data.terraform_remote_state.shared_vpc.outputs.svpc_host_project_id}/regions/${var.subnet_03_region}/subnetworks/${var.subnet_03_name}",
  ]

  activate_apis = [
    "compute.googleapis.com",
    "container.googleapis.com",
  ]
}

# Grant Compute Security Admin IAM role to the Kubernetes SA in the network host project
resource "google_project_iam_member" "dev1_gke_sa_security_admin_in_host" {
  project = data.terraform_remote_state.shared_vpc.outputs.svpc_host_project_id
  role    = "roles/compute.securityAdmin"
  member  = "serviceAccount:service-${module.create_dev1_project.project_number}@container-engine-robot.iam.gserviceaccount.com"

  depends_on = [
    null_resource.exec_check_for_dev1_gke_service_accounts
  ]

}

resource "null_resource" "exec_check_for_dev1_gke_service_accounts" {
  provisioner "local-exec" {
    command = <<EOT
      for (( c=1; c<=40; c++))
        do
          CHECK1=`gcloud projects get-iam-policy ${module.create_dev1_project.project_id} --format=json | jq '.bindings[]' | jq -r '. | select(.role == "roles/container.serviceAgent").members[]'`
          if [[ "$CHECK1" ]]; then
            echo "GKE service accounts created."
            break;
          fi

          echo "Waiting for GKE service accounts to be created."
          sleep 2
        done
    EOT

    interpreter = ["/bin/bash", "-c"]
  }
}