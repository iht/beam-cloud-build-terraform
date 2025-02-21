
locals {
  beam_modules = {
    "sdks/java" : "E2_HIGHCPU_32",
    "model" : "E2_HIGHCPU_32",
    "runners/core-java" : "E2_HIGHCPU_32",
    "runners/google-cloud-dataflow-java" : "E2_HIGHCPU_32",
    "runners/direct-java" : "E2_HIGHCPU_8",
    "runners/java-fn-execution" : "E2_HIGHCPU_8"
  }
}

module "beam_build_proj" {
  source = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/project?ref=v38.0.0"
  name   = var.project_id
  services = [
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com"
  ]
  project_create = false
}

module "beam_build_registry_docker" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/artifact-registry?ref=v38.0.0"
  project_id = module.beam_build_proj.project_id
  location   = var.region
  name       = "beam-build-docker"
  iam = {
    "roles/artifactregistry.admin" = ["serviceAccount:${module.beam_build_proj.number}@cloudbuild.gserviceaccount.com"]
  }
  cleanup_policy_dry_run = false
  cleanup_policies = {
    keep-5-versions = {
      action = "KEEP"
      most_recent_versions = {
        keep_count = 5
      }
    }
  }
}

module "beam_build_registry_maven" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/artifact-registry?ref=v38.0.0"
  project_id = module.beam_build_proj.project_id
  location   = var.region
  name       = "beam-build-maven"
  format     = { maven = {} }
  iam = {
    "roles/artifactregistry.admin" = ["serviceAccount:${module.beam_build_proj.number}@cloudbuild.gserviceaccount.com"]
  }
  cleanup_policy_dry_run = false
  cleanup_policies = {
    keep-5-versions = {
      action = "KEEP"
      most_recent_versions = {
        keep_count = 5
      }
    }
  }
}


resource "google_cloudbuild_trigger" "beam_container_trigger" {
  name     = "beam-cloud-builder-trigger"
  location = var.region
  project  = module.beam_build_proj.project_id

  github {
    owner = var.github_owner
    name  = var.container_repo
    push {
      branch = ".*"
    }
  }
  filename = "cloudbuild.yaml"
}


resource "google_cloudbuild_trigger" "build_beam_trigger" {
  for_each = local.beam_modules
  name     = join("-", ["beam", replace(each.key, "/", "-")])
  location = var.region
  project  = module.beam_build_proj.project_id

  github {
    owner = var.github_owner
    name  = var.beam_repo
    push {
      branch = ".*"
    }
  }

  build {
    timeout = "3600s"
    step {
      name   = "${var.region}-docker.pkg.dev/${module.beam_build_proj.project_id}/${module.beam_build_registry_docker.name}/beam-cloud-builder"
      script = <<SCRIPT
#!/usr/bin/env bash
echo "Set build version"
VERSION=`cat gradle.properties| grep "^version=" | cut -d '=' -f 2 | cut -d '-' -f 1`
COMMIT=`git rev-parse --short HEAD`
echo "Version is $VERSION-$COMMIT"
./release/src/main/scripts/set_version.sh $VERSION-$COMMIT
echo "Build Gradle project ${each.key}"
./gradlew -p ${each.key} -Ppublishing publishAllPublicationsToTestPublicationLocalRepository
SCRIPT
    }

    step {
      name   = "gcr.io/cloud-builders/gcloud"
      script = <<SCRIPT
#!/usr/bin/env bash
echo "Getting auth token"
gcloud auth print-access-token > /workspace/token_tmp.txt
SCRIPT
    }

    step {
      name   = "gcr.io/cloud-builders/mvn"
      script = <<SCRIPT
#!/usr/bin/env bash
token=`cat /workspace/token_tmp.txt`
find testPublication | grep pom$ | while read pom
do
fn=`echo $pom | rev | cut -f 2- -d '.' | rev`
jar=$fn.jar
echo "Publishing $pom"
mvn deploy:deploy-file -Durl=https://oauth2accesstoken:$token@${var.region}-maven.pkg.dev/${module.beam_build_proj.project_id}/${module.beam_build_registry_maven.name} -DpomFile=$pom -Dfile=$jar
echo "Done"
done
SCRIPT
    }

    options {
      machine_type          = each.value
      substitution_option   = "ALLOW_LOOSE"
      dynamic_substitutions = true
    }
  }
}
