# Kubernetes cluster with private node groups requires a network that is routed through NAT gateway.
resource "upcloud_router" "example2" {
  name = "example2-router"
}

resource "upcloud_gateway" "example2" {
  name     = "example2-nat-gateway"
  zone     = "fi-hel2"
  features = ["nat"]

  router {
    id = upcloud_router.example2.id
  }
}

resource "upcloud_network" "example2" {
  name = "example2-network"
  zone = "fi-hel2"
  ip_network {
    address            = "10.10.0.0/24"
    dhcp               = true
    family             = "IPv4"
    dhcp_default_route = true
  }
  router = upcloud_router.example2.id
}

resource "upcloud_kubernetes_cluster" "example2" {
  # Allow access to the cluster control plane from any external source.
  control_plane_ip_filter = ["0.0.0.0/0"]
  name                    = "example2-cluster"
  network                 = upcloud_network.example2.id
  zone                    = "fi-hel2"
  plan                    = "dev-md"
  private_node_groups     = true
}

# Create a Kubernetes cluster node group
resource "upcloud_kubernetes_node_group" "group" {
  cluster    = resource.upcloud_kubernetes_cluster.example2.id
  node_count = 2
  name       = "dev"
  plan       = "DEV-1xCPU-2GB"

  labels = {
    managedBy = "terraform"
  }

}

# Read the details of the newly created cluster
data "upcloud_kubernetes_cluster" "example" {
  id = upcloud_kubernetes_cluster.example2.id
}

# Set the Kubernetes provider credentials
provider "kubernetes" {
  client_certificate     = data.upcloud_kubernetes_cluster.example.client_certificate
  client_key             = data.upcloud_kubernetes_cluster.example.client_key
  cluster_ca_certificate = data.upcloud_kubernetes_cluster.example.cluster_ca_certificate
  host                   = data.upcloud_kubernetes_cluster.example.host
}

# In addition, write the kubeconfig to a file to interact with the cluster with `kubectl` or other clients
resource "local_file" "example" {
  content  = data.upcloud_kubernetes_cluster.example.kubeconfig
  filename = "example.conf"
}
