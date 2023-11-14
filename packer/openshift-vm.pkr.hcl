variable "gcp_project_id" {
  type        = string
  default     = "calyptia-playground-371615"
  description = "ID of the Project in Google Cloud"
}

variable "gcp_zone" {
  type        = string
  default     = "europe-west2-c"
  description = "Default zone to deploy in Google Cloud Platform"
}

variable "image_family" {
  type        = string
  default     = "test-calyptia-openshift-crc"
  description = "Template name for the images created"
}

variable "image_name" {
  type        = string
  default     = ""
  description = "Optional override for actual name for the images created"
}

locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
  # Handle the variable override in the lovely way you have to with HCL
  actual_image_name = "${var.image_name != "" ? var.image_name : "${var.image_family}-${local.timestamp}"}"
}

variable "username" {
  type        = string
  default     = "ubuntu"
  description = "Default username used to customize the base machine"
}

variable "disk_size" {
  type        = number
  description = "Size of disk for image in Gb"
  default     = 250
}

variable "pull_secret_file" {
  type        = string
  description = "Openshift Pull Secret"
  sensitive   = true
  default     = "./pull-secret.txt"
}

# For GCP we cannot specify multiple output locations so we use a template
source "googlecompute" "gcp_compute_calyptia" {
  image_family = var.image_family
  # image_name          = local.actual_image_name
  image_description   = "Openshift CRC installed into a VM"
  machine_type        = "c2-standard-8"
  project_id          = var.gcp_project_id
  source_image_family = "ubuntu-2204-lts"
  ssh_username        = var.username
  zone                = var.gcp_zone
  disk_size           = "${var.disk_size}"
  # We need nested virtualisation for CRC
  enable_nested_virtualization = true
  image_labels = {
    # A label can only contain lowercase letters, numeric characters, underscores and dashes. The value can be at most 63 characters long.
    source-image = "ubuntu-2204-lts"
  }
}

build {
  # For GCP we cannot specify multiple output locations so we use a template
  # and override the default location for each instance.
  source "source.googlecompute.gcp_compute_calyptia.us" {
    name       = "us"
    image_name = "${local.actual_image_name}-us"
    image_storage_locations = [
      "us"
    ]
  }

  source "source.googlecompute.gcp_compute_calyptia.eu" {
    name = "eu"

    image_name = "${local.actual_image_name}-eu"
    image_storage_locations = [
      "eu"
    ]
  }

  source "source.googlecompute.gcp_compute_calyptia.asia" {
    name = "asia"

    image_name = "${local.actual_image_name}-asia"
    image_storage_locations = [
      "asia"
    ]
  }

  # Wait for any cloud-init to complete before we do anything else - it can trigger
  # a race condition for package installation issues.
  provisioner "shell" {
    inline = [
      "/usr/bin/cloud-init status --wait",
      "mkdir -p /home/${var.username}/.config/crc"
    ]
  }

  provisioner "file" {
    source      = var.pull_secret_file
    destination = "/home/${var.username}/.config/crc/pull-secret.txt"
  }


  provisioner "shell" {
    script  = "./provision-crc.sh"
    timeout = "5m"
    env = {
      OPENSHIFT_PULL_SECRET = "/home/${var.username}/.config/crc/pull-secret.txt"
    }
  }

  # Force a reboot to reload the shell otherwise the SSH connection is reused.
  # We need this to ensure group membership and services are correct.
  provisioner "shell" {
    inline = [
      "sudo reboot"
    ]
    expect_disconnect = true
  }

  provisioner "shell" {
    pause_before        = "10s"
    inline = [
      "/usr/local/bin/crc setup --log-level debug"
    ]
    timeout = "5m"
  }

  # Start CRC to pre-pull images
  provisioner "shell" {
    inline = [
      "/usr/local/bin/crc start --log-level debug"
    ]
    timeout = "10m"
  }

  # Now do a clean shut down of CRC
  provisioner "shell" {
    inline = [
      "/usr/local/bin/crc stop --log-level debug"
    ]
    timeout = "5m"
  }
}
