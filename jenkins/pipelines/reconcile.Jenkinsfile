pipeline {
  agent any

  options {
    disableConcurrentBuilds()
    skipDefaultCheckout()
  }

  triggers {
    cron('* * * * *')
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Reconcile') {
      steps {
        withCredentials([file(credentialsId: 'aks-kubeconfig', variable: 'KUBECONFIG')]) {
          sh 'kubectl apply -f jenkins/manifests/'
        }
      }
    }
  }
}
