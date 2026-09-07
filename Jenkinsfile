pipeline {
  agent any
  parameters {
    booleanParam(name: 'RUN_ROLLBACK', defaultValue: false, description: 'Run explicit image and data rollback')
    string(name: 'KOPIA_SNAPSHOT_ID', defaultValue: '', description: 'Pre-deploy Kopia snapshot ID')
    string(name: 'ROLLBACK_IMAGE', defaultValue: '', description: 'Immutable image to restore')
  }
  environment { REGISTRY_HOST = 'gmo021.cansportsvg.com:9443'; VM_IP = '10.13.31.15'; DEPLOY_USER = 'psserver' }
  stages {
    stage('Checkout') { steps { checkout scm; script { env.IMAGE_REF = "${env.REGISTRY_HOST}/library/eac-demo:${env.GIT_COMMIT}" } } }
    stage('Unit Test') { when { expression { return !params.RUN_ROLLBACK } } steps { dir('app') { sh 'npm ci && npm test' } } }
    stage('Build Image') { when { expression { return !params.RUN_ROLLBACK } } steps { sh 'docker build -t "$IMAGE_REF" -f docker/Dockerfile .' } }
    stage('Push Registry') { when { expression { return !params.RUN_ROLLBACK } } steps { withCredentials([usernamePassword(credentialsId: 'REGISTRY_CREDENTIALS', usernameVariable: 'REGISTRY_USERNAME', passwordVariable: 'REGISTRY_PASSWORD')]) { sh 'set +x; printf %s "$REGISTRY_PASSWORD" | docker login "$REGISTRY_HOST" --username "$REGISTRY_USERNAME" --password-stdin; docker push "$IMAGE_REF"' } } }
    stage('Terraform Apply') { when { expression { return !params.RUN_ROLLBACK } } steps { withCredentials([sshUserPrivateKey(credentialsId: 'DEPLOY_SSH_KEY', keyFileVariable: 'SSH_KEY', usernameVariable: 'DEPLOY_USER')]) { dir('terraform') { sh 'set +x; TF_VAR_deploy_ssh_public_key="$(ssh-keygen -y -f "$SSH_KEY")" terraform init -input=false && TF_VAR_deploy_ssh_public_key="$(ssh-keygen -y -f "$SSH_KEY")" terraform apply -auto-approve -input=false' } } } }
    stage('Ansible Configure') { when { expression { return !params.RUN_ROLLBACK } } steps { withCredentials([file(credentialsId: 'REGISTRY_CA_CERT', variable: 'REGISTRY_CA_CERT_PATH'), string(credentialsId: 'POSTGRES_PASSWORD', variable: 'POSTGRES_PASSWORD')]) { dir('ansible') { sh 'set +x; ansible-playbook playbooks/configure.yml -e "registry_ca_cert_path=$REGISTRY_CA_CERT_PATH" -e "postgres_password=$POSTGRES_PASSWORD"' } } } }
    stage('Integration Test') { when { expression { return !params.RUN_ROLLBACK } } steps { sh 'curl --fail --retry 10 "http://$VM_IP:8080/health"' } }
    stage('Pre-deploy Kopia Snapshot') { when { expression { return !params.RUN_ROLLBACK } } steps { sshagent(credentials: ['DEPLOY_SSH_KEY']) { script { env.PREVIOUS_IMAGE = sh(script: 'ssh $DEPLOY_USER@$VM_IP "cat /srv/eac-demo/state/current-image 2>/dev/null || true"', returnStdout: true).trim() } withCredentials([usernamePassword(credentialsId: 'KOPIA_CREDENTIALS', usernameVariable: 'KOPIA_USERNAME', passwordVariable: 'KOPIA_PASSWORD')]) { sh 'set +x; ssh $DEPLOY_USER@$VM_IP "KOPIA_SERVER=\"$KOPIA_SERVER\" KOPIA_USERNAME=\"$KOPIA_USERNAME\" KOPIA_PASSWORD=\"$KOPIA_PASSWORD\" bash -s" < scripts/backup.sh | tee snapshot.log' } script { env.SNAPSHOT_LOG = readFile('snapshot.log').trim() } } } }
    stage('Deploy') { when { expression { return !params.RUN_ROLLBACK } } steps { sshagent(credentials: ['DEPLOY_SSH_KEY']) { sh 'ssh $DEPLOY_USER@$VM_IP "bash -s -- \"$IMAGE_REF\"" < scripts/deploy.sh' } } }
    stage('Health Check') { when { expression { return !params.RUN_ROLLBACK } } steps { sshagent(credentials: ['DEPLOY_SSH_KEY']) { sh 'ssh $DEPLOY_USER@$VM_IP "bash -s -- \"${IMAGE_REF##*:}\"" < scripts/health-check.sh' } } }
    stage('Rollback') { when { expression { return params.RUN_ROLLBACK } } steps { input message: 'Approve explicit rollback of image and persistent data', ok: 'Rollback'; sshagent(credentials: ['DEPLOY_SSH_KEY']) { withCredentials([usernamePassword(credentialsId: 'KOPIA_CREDENTIALS', usernameVariable: 'KOPIA_USERNAME', passwordVariable: 'KOPIA_PASSWORD')]) { sh 'set +x; ssh $DEPLOY_USER@$VM_IP "KOPIA_SERVER=\"$KOPIA_SERVER\" KOPIA_USERNAME=\"$KOPIA_USERNAME\" KOPIA_PASSWORD=\"$KOPIA_PASSWORD\" bash -s -- \"$KOPIA_SNAPSHOT_ID\" \"$ROLLBACK_IMAGE\"" < scripts/rollback.sh' } } } }
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
