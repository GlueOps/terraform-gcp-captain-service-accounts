
variable "svc_accounts_and_roles" {
  description = "Create service accounts and assign roles"
}

variable "gcp_project_name" {
  description = "gcp project name"
}

locals {

  svc_accounts = var.svc_accounts_and_roles
  #   {
  #     terraform-cloud-operator = toset(["roles/owner"])
  #     hashicorp-vault          = toset(["roles/cloudkms.cryptoKeyEncrypterDecrypter"])
  #   }

  svc_accounts_flat = flatten([
    for k, v in local.svc_accounts : [
      for i in v : {
        name = k
        role = i
      }
    ]
  ])

}

data "google_projects" "app_project" {
  filter = "lifecycleState:ACTIVE name:${var.gcp_project_name}" #parent.id:${local.gcp_folder_id}"
}

resource "google_project_iam_binding" "svc_account" {
  for_each = { for x in local.svc_accounts_flat : "${x.name}-${x.role}" => x }
  project  = data.google_projects.app_project.projects[0].project_id
  role     = each.value.role

  members = [
    "serviceAccount:${each.value.name}@${data.google_projects.app_project.projects[0].project_id}.iam.gserviceaccount.com",
  ]
}

resource "google_service_account" "project_level_svc_account" {
  for_each     = local.svc_accounts
  project      = data.google_projects.app_project.projects[0].project_id
  account_id   = each.key
  display_name = each.key
}


// generate a service account key for each service account and save to a local json file on disk
resource "google_service_account_key" "project_level_svc_account_key" {
  project            = data.google_projects.app_project.projects[0].project_id
  for_each           = google_service_account.project_level_svc_account
  service_account_id = each.key
  public_key_type    = "TYPE_X509_PEM_FILE"
  depends_on = [
    google_project_iam_binding.svc_account
  ]
}


resource "local_file" "project_level_svc_account_key" {
  for_each = google_service_account_key.project_level_svc_account_key
  content  = base64encode(replace(base64decode(each.value.private_key), "\n", ""))
  filename = "./gcp-service-account-keys/${each.key}.jb64"

  depends_on = [
    google_service_account_key.project_level_svc_account_key
  ]

}
