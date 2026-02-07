provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

resource "cloudflare_dns_record" "records" {
  for_each = var.records
  zone_id  = var.zone_id
  name     = each.key
  ttl      = each.value.ttl
  type     = each.value.type
  content  = each.value.ip
  proxied  = false
}

# Kubernetes cluster with private node groups requires a network that is routed through NAT gateway.
resource "upcloud_router" "kube-router" {
  name = "kube-router"
}

resource "upcloud_gateway" "kube" {
  name     = "kube-nat-gateway"
  zone     = "fi-hel2"
  features = ["nat"]

  router {
    id = upcloud_router.kube-router.id
  }
}

resource "upcloud_network" "kube-network" {
  name = "kube-network"
  zone = "fi-hel2"
  ip_network {
    address            = "10.10.0.0/24"
    dhcp               = true
    family             = "IPv4"
    dhcp_default_route = true
  }
  router = upcloud_router.kube-router.id
}

resource "upcloud_kubernetes_cluster" "kube-cluster" {
  # Allow access to the cluster control plane from any external source.
  control_plane_ip_filter = ["0.0.0.0/0"]
  name                    = "kube-cluster"
  network                 = upcloud_network.kube-network.id
  zone                    = "fi-hel2"
  plan                    = "dev-md"
  private_node_groups     = true
}

# Create a Kubernetes cluster node group
resource "upcloud_kubernetes_node_group" "kube-dev-node-group" {
  cluster    = resource.upcloud_kubernetes_cluster.kube-cluster.id
  node_count = 2
  name       = "dev"
  plan       = "DEV-1xCPU-2GB"

  labels = {
    managedBy = "terraform"
  }

}

# Read the details of the newly created cluster
data "upcloud_kubernetes_cluster" "kube-cluster" {
  id = upcloud_kubernetes_cluster.kube-cluster.id
}

# Set the Kubernetes provider credentials
provider "kubernetes" {
  client_certificate     = data.upcloud_kubernetes_cluster.kube-cluster.client_certificate
  client_key             = data.upcloud_kubernetes_cluster.kube-cluster.client_key
  cluster_ca_certificate = data.upcloud_kubernetes_cluster.kube-cluster.cluster_ca_certificate
  host                   = data.upcloud_kubernetes_cluster.kube-cluster.host
}

provider "helm" {
  kubernetes = {
    host = data.upcloud_kubernetes_cluster.kube-cluster.host

    client_certificate     = data.upcloud_kubernetes_cluster.kube-cluster.client_certificate
    client_key             = data.upcloud_kubernetes_cluster.kube-cluster.client_key
    cluster_ca_certificate = data.upcloud_kubernetes_cluster.kube-cluster.cluster_ca_certificate
  }
}

# In addition, write the kubeconfig to a file to interact with the cluster with `kubectl` or other clients
resource "local_file" "kubeconfig" {
  content  = data.upcloud_kubernetes_cluster.kube-cluster.kubeconfig
  filename = "kubeconfig"
}

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  version          = "9.4.1"
  chart            = "argo-cd"
  create_namespace = true

  values = [
    file("${path.module}/argocd/values.yaml")
  ]
}

resource "kubernetes_manifest" "infra-repo" {
  manifest = yamldecode(<<-EOF
    apiVersion: v1
    kind: Secret
    metadata:
      name: config-repository
      namespace: ${helm_release.argocd.namespace}
      labels:
        argocd.argoproj.io/secret-type: repository
    data:
      type: ${base64encode("git")}
      url: ${base64encode("https://github.com/AnttiRae/upcloud-test-infra.git")}
    EOF
  )

  depends_on = [
    helm_release.argocd
  ]
}

resource "kubernetes_manifest" "app-of-apps" {
  manifest = yamldecode(<<-EOF
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: argocd-app-of-apps
      namespace: argocd
    spec:
      project: default
      source:
        repoURL: https://github.com/AnttiRae/upcloud-test-infra.git
        targetRevision: HEAD
        path: argocd-config/app-of-apps
        directory:
          recurse: true
      destination:
        server: https://kubernetes.default.svc
        namespace: argocd
      syncPolicy:
        automated:
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
  EOF
  )
}
