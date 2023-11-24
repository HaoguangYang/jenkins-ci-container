FROM jenkins/jenkins:alpine-jdk21

ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"
ENV JENKINS_USER admin
ENV JENKINS_PASS admin

USER root

RUN chown -R jenkins:jenkins /var/jenkins_home

USER jenkins

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugins "$(cat /usr/share/jenkins/ref/plugins.txt | tr '\n' ' ')"

COPY agent.dockerfile /usr/share/jenkins/ref/agent.dockerfile
