pipeline {
  agent any

  options {
    disableConcurrentBuilds()
    skipDefaultCheckout()
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Deploy') {
      steps {
        withCredentials([file(credentialsId: 'aks-kubeconfig', variable: 'KUBECONFIG')]) {
          sh 'kubectl apply -f jenkins/manifests/'
        }
      }
    }

    stage('Wait for rollout') {
      steps {
        withCredentials([file(credentialsId: 'aks-kubeconfig', variable: 'KUBECONFIG')]) {
          sh 'kubectl rollout status deployment/backend -n budget-tracker --timeout=180s'
          sh 'kubectl rollout status deployment/frontend -n budget-tracker --timeout=180s'
        }
      }
    }
  }
}
