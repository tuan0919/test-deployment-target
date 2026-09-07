pipeline {
  agent any

  parameters {
    booleanParam(name: 'RUN_ROLLBACK', defaultValue: false, description: 'Run explicit image and data rollback')
    string(name: 'KOPIA_SNAPSHOT_ID', defaultValue: '', description: 'Pre-deploy Kopia snapshot ID')
    string(name: 'ROLLBACK_IMAGE', defaultValue: '', description: 'Immutable image to restore')
  }

  environment {
    REGISTRY_HOST = 'gmo021.cansportsvg.com:9443'
    VM_IP = '10.13.31.15'
    DEPLOY_USER = 'psserver'
    BUILD_HOST = '10.13.34.176'
    BUILD_USER = 'gmo021'
    BUILD_WORKSPACE = '/home/gmo021/jenkins-build/test-deployment-target'
  }

  stages {
    stage('Prepare Build Host') {
      when {
        expression { return !params.RUN_ROLLBACK }
      }
      steps {
        withCredentials([sshUserPrivateKey(credentialsId: 'BUILD_HOST_SSH_KEY', keyFileVariable: 'BUILD_SSH_KEY', usernameVariable: 'BUILD_SSH_USER')]) {
          script {
            def revision = sh(script: '''ssh -i "$BUILD_SSH_KEY" -o StrictHostKeyChecking=accept-new "$BUILD_SSH_USER@$BUILD_HOST" "set -e; if [ ! -d \"$BUILD_WORKSPACE/.git\" ]; then timeout 60 git clone git@github.com:tuan0919/test-deployment-target.git \"$BUILD_WORKSPACE\"; fi; cd \"$BUILD_WORKSPACE\"; git remote set-url origin git@github.com:tuan0919/test-deployment-target.git; timeout 60 git fetch origin main; git checkout -f origin/main; git clean -fdx; git rev-parse HEAD"''', returnStdout: true).trim()
            env.IMAGE_REF = "${env.REGISTRY_HOST}/library/eac-demo:${revision}"
          }
        }
      }
    }

    stage('Unit Test') {
      when {
        expression { return !params.RUN_ROLLBACK }
      }
      steps {
        withCredentials([sshUserPrivateKey(credentialsId: 'BUILD_HOST_SSH_KEY', keyFileVariable: 'BUILD_SSH_KEY', usernameVariable: 'BUILD_SSH_USER')]) {
          sh '''ssh -i "$BUILD_SSH_KEY" "$BUILD_SSH_USER@$BUILD_HOST" "cd '$BUILD_WORKSPACE/app' && bash -lic 'npm ci && npm test'"'''
        }
      }
    }

    stage('Build Image') {
      when {
        expression { return !params.RUN_ROLLBACK }
      }
      steps {
        withCredentials([sshUserPrivateKey(credentialsId: 'BUILD_HOST_SSH_KEY', keyFileVariable: 'BUILD_SSH_KEY', usernameVariable: 'BUILD_SSH_USER')]) {
          sh 'ssh -i "$BUILD_SSH_KEY" "$BUILD_SSH_USER@$BUILD_HOST" "cd \"$BUILD_WORKSPACE\" && docker build -t \"$IMAGE_REF\" -f docker/Dockerfile ."'
        }
      }
    }

    stage('Push Registry') {
      when {
        expression { return !params.RUN_ROLLBACK }
      }
      steps {
        withCredentials([usernamePassword(credentialsId: 'REGISTRY_CREDENTIALS', usernameVariable: 'REGISTRY_USERNAME', passwordVariable: 'REGISTRY_PASSWORD')]) {
          withCredentials([sshUserPrivateKey(credentialsId: 'BUILD_HOST_SSH_KEY', keyFileVariable: 'BUILD_SSH_KEY', usernameVariable: 'BUILD_SSH_USER')]) {
            sh 'set +x; printf %s "$REGISTRY_PASSWORD" | ssh -i "$BUILD_SSH_KEY" "$BUILD_SSH_USER@$BUILD_HOST" "cd \"$BUILD_WORKSPACE\" && docker login \"$REGISTRY_HOST\" --username \"$REGISTRY_USERNAME\" --password-stdin && docker push \"$IMAGE_REF\""'
          }
        }
      }
    }

    stage('Terraform Apply') {
      when {
        expression { return !params.RUN_ROLLBACK }
      }
      steps {
        withCredentials([sshUserPrivateKey(credentialsId: 'DEPLOY_SSH_KEY', keyFileVariable: 'DEPLOY_KEY_FILE', usernameVariable: 'DEPLOY_SSH_USER'), sshUserPrivateKey(credentialsId: 'BUILD_HOST_SSH_KEY', keyFileVariable: 'BUILD_SSH_KEY', usernameVariable: 'BUILD_SSH_USER')]) {
          sh '''set +x
            DEPLOY_PUBLIC_KEY="$(ssh-keygen -y -f "$DEPLOY_KEY_FILE")"
            ssh -i "$BUILD_SSH_KEY" "$BUILD_SSH_USER@$BUILD_HOST" \
              "cd '$BUILD_WORKSPACE/terraform' && TF_VAR_deploy_ssh_public_key='$DEPLOY_PUBLIC_KEY' terraform init -input=false && TF_VAR_deploy_ssh_public_key='$DEPLOY_PUBLIC_KEY' terraform apply -auto-approve -input=false"
          '''
        }
      }
    }

    stage('Ansible Configure') {
      when {
        expression { return !params.RUN_ROLLBACK }
      }
      steps {
        withCredentials([file(credentialsId: 'REGISTRY_CA_CERT', variable: 'REGISTRY_CA_CERT_PATH'), string(credentialsId: 'POSTGRES_PASSWORD', variable: 'POSTGRES_PASSWORD'), sshUserPrivateKey(credentialsId: 'DEPLOY_SSH_KEY', keyFileVariable: 'DEPLOY_KEY_FILE', usernameVariable: 'DEPLOY_SSH_USER'), sshUserPrivateKey(credentialsId: 'BUILD_HOST_SSH_KEY', keyFileVariable: 'BUILD_SSH_KEY', usernameVariable: 'BUILD_SSH_USER')]) {
          sh '''set +x
            REMOTE_CA_CERT=/tmp/jenkins-registry-ca.pem
            REMOTE_DEPLOY_KEY=/tmp/jenkins-deploy-key
            cleanup() {
              ssh -i "$BUILD_SSH_KEY" "$BUILD_SSH_USER@$BUILD_HOST" "rm -f '$REMOTE_CA_CERT' '$REMOTE_DEPLOY_KEY'"
            }
            trap cleanup EXIT
            scp -i "$BUILD_SSH_KEY" "$REGISTRY_CA_CERT_PATH" "$BUILD_SSH_USER@$BUILD_HOST:$REMOTE_CA_CERT"
            scp -i "$BUILD_SSH_KEY" "$DEPLOY_KEY_FILE" "$BUILD_SSH_USER@$BUILD_HOST:$REMOTE_DEPLOY_KEY"
            ssh -i "$BUILD_SSH_KEY" "$BUILD_SSH_USER@$BUILD_HOST" \
              "chmod 600 '$REMOTE_DEPLOY_KEY' && cd '$BUILD_WORKSPACE/ansible' && ansible-playbook playbooks/configure.yml -e 'ansible_ssh_private_key_file=$REMOTE_DEPLOY_KEY' -e 'registry_ca_cert_path=$REMOTE_CA_CERT' -e 'postgres_password=$POSTGRES_PASSWORD'"
          '''
          }
        }
      }

    stage('Integration Test') {
      when {
        expression { return !params.RUN_ROLLBACK }
      }
      steps {
        sh 'curl --fail --retry 10 "http://$VM_IP:8080/health"'
      }
    }

    stage('Pre-deploy Kopia Snapshot') {
      when {
        expression { return !params.RUN_ROLLBACK }
      }
      steps {
        sshagent(credentials: ['DEPLOY_SSH_KEY']) {
          script {
            env.PREVIOUS_IMAGE = sh(script: 'ssh $DEPLOY_USER@$VM_IP "cat /srv/eac-demo/state/current-image 2>/dev/null || true"', returnStdout: true).trim()
          }
          withCredentials([usernamePassword(credentialsId: 'KOPIA_CREDENTIALS', usernameVariable: 'KOPIA_USERNAME', passwordVariable: 'KOPIA_PASSWORD')]) {
            sh 'set +x; ssh $DEPLOY_USER@$VM_IP "KOPIA_SERVER=\"$KOPIA_SERVER\" KOPIA_USERNAME=\"$KOPIA_USERNAME\" KOPIA_PASSWORD=\"$KOPIA_PASSWORD\" bash -s" < scripts/backup.sh | tee snapshot.log'
          }
          script {
            env.SNAPSHOT_LOG = readFile('snapshot.log').trim()
          }
        }
      }
    }

    stage('Deploy') {
      when {
        expression { return !params.RUN_ROLLBACK }
      }
      steps {
        sshagent(credentials: ['DEPLOY_SSH_KEY']) {
          sh 'ssh $DEPLOY_USER@$VM_IP "bash -s -- \"$IMAGE_REF\"" < scripts/deploy.sh'
        }
      }
    }

    stage('Health Check') {
      when {
        expression { return !params.RUN_ROLLBACK }
      }
      steps {
        sshagent(credentials: ['DEPLOY_SSH_KEY']) {
          sh 'ssh $DEPLOY_USER@$VM_IP "bash -s -- \"${IMAGE_REF##*:}\"" < scripts/health-check.sh'
        }
      }
    }

    stage('Rollback') {
      when {
        expression { return params.RUN_ROLLBACK }
      }
      steps {
        input message: 'Approve explicit rollback of image and persistent data', ok: 'Rollback'
        sshagent(credentials: ['DEPLOY_SSH_KEY']) {
          withCredentials([usernamePassword(credentialsId: 'KOPIA_CREDENTIALS', usernameVariable: 'KOPIA_USERNAME', passwordVariable: 'KOPIA_PASSWORD')]) {
            sh 'set +x; ssh $DEPLOY_USER@$VM_IP "KOPIA_SERVER=\"$KOPIA_SERVER\" KOPIA_USERNAME=\"$KOPIA_USERNAME\" KOPIA_PASSWORD=\"$KOPIA_PASSWORD\" bash -s -- \"$KOPIA_SNAPSHOT_ID\" \"$ROLLBACK_IMAGE\"" < scripts/rollback.sh'
          }
        }
      }
    }
  }

  post {
    always {
      script {
        writeFile file: 'rollback-context.json', text: groovy.json.JsonOutput.toJson([previousImage: env.PREVIOUS_IMAGE ?: '', snapshotOutput: env.SNAPSHOT_LOG ?: ''])
        archiveArtifacts artifacts: 'rollback-context.json,snapshot.log', allowEmptyArchive: true
      }
    }
  }
}
