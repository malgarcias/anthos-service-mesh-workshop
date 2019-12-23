mkdir -p tmp
gsutil cp gs://${tfadmin_proj?env not set}/ops/k8s/cloudbuild.yaml tmp/cloudbuild.yaml
mkdir -p tmp/${ops_gke_1_name?env not set}/istio-controlplane
mkdir -p tmp/${ops_gke_2_name?env not set}/istio-controlplane
mkdir -p tmp/${dev1_gke_1_name?env not set}/istio-controlplane
mkdir -p tmp/${dev1_gke_2_name?env not set}/istio-controlplane
mkdir -p tmp/${dev2_gke_3_name?env not set}/istio-controlplane
mkdir -p tmp/${dev2_gke_4_name?env not set}/istio-controlplane

# Copy core resources to every cluster
echo $(ls -d tmp/*/) | xargs -n 1 cp config/istio-system-namespace.yaml
echo $(ls -d tmp/*/) | xargs -n 1 cp config/istio-system-psp.yaml
echo $(ls -d tmp/*/) | xargs -n 1 cp config/istio-system-rbac.yaml
echo $(ls -d tmp/*/) | xargs -n 1 cp config/istio-operator-psp.yaml
echo $(ls -d tmp/*/) | xargs -n 1 cp config/jsonpatch-istio-operator-clusterrole.yaml
echo $(ls -d tmp/*/) | xargs -n 1 cp config/kustomization.yaml
echo $(ls -d tmp/*/istio-controlplane) | xargs -n 1 cp config/istio-controlplane/kustomization.yaml

# Copy downloaded isto operator to every cluster
gsutil -m cp -r gs://${tfadmin_proj}/ops/istio-operator-${istio_version?env not set} .
mv istio-operator-${istio_version} istio-operator
echo $(ls -d tmp/*/) | xargs -n 1 cp -r istio-operator
rm -Rf istio-operator*

# Copy generated CA certs to every cluster.
gsutil cp -r gs://${tfadmin_proj}/ops/istiocerts .
kubectl create secret generic -n istio-system \
--from-file=istiocerts/ca-cert.pem \
--from-file=istiocerts/ca-key.pem \
--from-file=istiocerts/root-cert.pem \
--from-file=istiocerts/cert-chain.pem \
--dry-run cacerts -oyaml > istio-cacerts.yaml
echo $(ls -d tmp/*/istio-controlplane/) | xargs -n 1 cp istio-cacerts.yaml
rm -Rf istiocerts*

cat - | tee tmp/README.md << EOF
This is where the k8s manifests live.
EOF

# Add cacerts to all controlplane kustomizations
for d in $(ls -d tmp/*/istio-controlplane); do
  (cd $d && kustomize edit add resource istio-cacerts.yaml)
done

# Patch ops 1 cluster istio controlplane CR with static ILB IPs
SRC="config/istio-controlplane/istio-replicated-controlplane.yaml"
DEST="tmp/${ops_gke_1_name}/istio-controlplane/$(basename $SRC)"
sed \
  -e "s/POLICY_ILB_IP/${ops_gke_1_policy_ilb?env not set}/g" \
  -e "s/TELEMETRY_ILB_IP/${ops_gke_1_telemetry_ilb?env not set}/g" \
  -e "s/PILOT_ILB_IP/${ops_gke_1_pilot_ilb?env not set}/g" \
  $SRC | tee $DEST

# Update kustomization
(cd $(dirname $DEST) && kustomize edit add resource $(basename $DEST))

# Patch ops 2 cluster istio controlplane CR with static ILB IPs
SRC="config/istio-controlplane/istio-replicated-controlplane.yaml"
DEST="tmp/${ops_gke_2_name}/istio-controlplane/$(basename $SRC)"
sed \
  -e "s/POLICY_ILB_IP/${ops_gke_2_policy_ilb?env not set}/g" \
  -e "s/TELEMETRY_ILB_IP/${ops_gke_2_telemetry_ilb?env not set}/g" \
  -e "s/PILOT_ILB_IP/${ops_gke_2_pilot_ilb?env not set}/g" \
  $SRC | tee $DEST

# Update kustomization
(cd $(dirname $DEST) && kustomize edit add resource $(basename $DEST))

# Patch dev 1 clusters 1 and 2 with ILB IPs from ops 1.
for cluster in ${dev1_gke_1_name} ${dev1_gke_2_name}; do
  SRC="config/istio-controlplane/istio-shared-controlplane.yaml"
  DEST="tmp/$cluster/istio-controlplane/$(basename $SRC)"
  sed \
    -e "s/POLICY_ILB_IP/${ops_gke_1_policy_ilb}/g" \
    -e "s/TELEMETRY_ILB_IP/${ops_gke_1_telemetry_ilb}/g" \
    -e "s/PILOT_ILB_IP/${ops_gke_1_pilot_ilb}/g" \
    $SRC | tee $DEST
  
  # Update kustomization
  (cd $(dirname $DEST) && kustomize edit add resource $(basename $DEST))
done

# Patch dev 2 clusters 3 and 4 with ILB IPs from ops 2.
for cluster in ${dev2_gke_3_name} ${dev2_gke_4_name}; do
  SRC="config/istio-controlplane/istio-shared-controlplane.yaml"
  DEST="tmp/$cluster/istio-controlplane/$(basename $SRC)"
  sed \
    -e "s/POLICY_ILB_IP/${ops_gke_2_policy_ilb}/g" \
    -e "s/TELEMETRY_ILB_IP/${ops_gke_2_telemetry_ilb}/g" \
    -e "s/PILOT_ILB_IP/${ops_gke_2_pilot_ilb}/g" \
    $SRC | tee $DEST
  
  # Update kustomization
  (cd $(dirname $DEST) && kustomize edit add resource $(basename $DEST))
done

# Copy script used to setup multi-cluster service discovery
cp -r config/kubeconfigs tmp/
cp config/make_multi_cluster_config.sh tmp/

# Copy repo files, overwrite existing files.
rm -Rf k8s-repo
git config --global user.email $(gcloud auth list --filter=status:ACTIVE --format='value(account)')
git config --global user.name "terraform"
git config --global credential.'https://source.developers.google.com'.helper gcloud.sh
gcloud source repos clone ${k8s_repo_name?env not set} --project=${ops_project_id?env not set}
cp -r tmp/. ${k8s_repo_name}
cd ${k8s_repo_name}
git add . && git commit -am "cloudbuild"
git push -u origin master