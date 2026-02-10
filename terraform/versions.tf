terraform {
  required_version = ">= 1.9.0"

  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.8.1"
    }
  }
}

provider "libvirt" {
  uri = var.libvirt_uri
}
