#!/usr/bin/env bash
set -euo pipefail

# Runs directly on the Jenkins VM via SSH.
# Installs Java 17, Jenkins LTS, and kubectl.
# Called by setup-jenkins.sh — do not run manually unless debugging.
JENKINS_VERSION="2.555.3"

echo "==> Installing Java 21..."
sudo apt-get update -q
sudo apt-get install -y fontconfig openjdk-21-jre

echo "==> Adding Jenkins apt repository..."
sudo rm -f /usr/share/keyrings/jenkins-keyring.asc \
            /usr/share/keyrings/jenkins-keyring.gpg \
            /etc/apt/sources.list.d/jenkins.list
sudo curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key | sudo tee \
  /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null

echo "==> Installing Jenkins ($JENKINS_VERSION)..."
sudo apt-get update -q
sudo apt-get install -y "jenkins=$JENKINS_VERSION"
# Prevent unattended-upgrades from bumping Jenkins mid-measurement.
sudo apt-mark hold jenkins

echo "==> Capping JVM heap at 512m and disabling setup wizard..."
echo 'JAVA_OPTS=-Xmx512m -Xms256m -Djenkins.install.runSetupWizard=false' | sudo tee -a /etc/default/jenkins > /dev/null

echo "==> Installing kubectl..."
curl -sLO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

echo "==> Starting Jenkins..."
sudo systemctl enable jenkins
sudo systemctl start jenkins

echo ""
echo "==> Install complete."
sudo systemctl status jenkins --no-pager
