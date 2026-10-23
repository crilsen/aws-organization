pipeline {
  agent none
  options {
    skipDefaultCheckout(true)
    disableConcurrentBuilds()
    timestamps()
  }
  parameters {
    choice(name: 'TF_ACTION', choices: ['validate', 'plan', 'apply'], description: 'Select the operation for this build.')
    choice(name: 'TF_STACK', choices: ['organization', 'identity-center'], description: 'Stack for plan or apply.')
  }
  stages {
    stage('Validate') {
      agent { label 'terraform-validate' }
      steps {
        checkout scm
        sh 'bash scripts/ci/terraform.sh validate'
      }
    }
    stage('Plan') {
      when {
        allOf {
          branch 'main'
          expression { params.TF_ACTION == 'plan' || params.TF_ACTION == 'apply' }
        }
      }
      agent { label 'terraform-plan' }
      steps {
        checkout scm
        sh '''
          set -eu
          export CI_ENGINE=jenkins CI_RUN_ID="$BUILD_NUMBER" CI_COMMIT_SHA="$(git rev-parse HEAD)" CI_REF="$BRANCH_NAME"
          export TF_METADATA_FILE=ci-plan.env
          bash scripts/ci/terraform.sh plan "$TF_STACK"
        '''
        stash name: 'plan-metadata', includes: 'ci-plan.env'
      }
    }
    stage('Approve apply') {
      when {
        allOf {
          branch 'main'
          expression { params.TF_ACTION == 'apply' }
        }
      }
      input {
        message 'Review the encrypted plan in private S3 before applying it.'
        ok 'Apply reviewed plan'
      }
      steps {
        echo 'Apply approved in Jenkins.'
      }
    }
    stage('Apply') {
      when {
        allOf {
          branch 'main'
          expression { params.TF_ACTION == 'apply' }
        }
      }
      agent { label 'terraform-apply' }
      steps {
        checkout scm
        unstash 'plan-metadata'
        sh '''
          set -eu
          set -a
          . ./ci-plan.env
          set +a
          export CI_ENGINE=jenkins CI_RUN_ID="$BUILD_NUMBER" CI_COMMIT_SHA="$(git rev-parse HEAD)" CI_REF="$BRANCH_NAME"
          export CI_APPLY_APPROVED=yes
          export CI_APPLY_GATE_ACK="$APPLY_GATE_ACK"
          bash scripts/ci/terraform.sh apply "$TF_STACK"
        '''
      }
    }
  }
}
