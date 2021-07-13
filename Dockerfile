# Use 1.8-26 version to pick up JDK 1.8u282.
FROM registry.redhat.io/redhat-openjdk-18/openjdk18-openshift:1.8-26

ENV FUSE_KARAF_IMAGE_NAME=fuse7/fuse-karaf-openshift \
    FUSE_KARAF_IMAGE_VERSION=1.8 \
    JOLOKIA_VERSION=1.6.2.redhat-00002 \
    KARAF_FRAMEWORK_VERSION=4.2.9.fuse-780023-redhat-00001 \
    PROMETHEUS_JMX_EXPORTER_VERSION=0.3.1.redhat-00006 \
    PATH="/usr/local/s2i:$PATH" \
    AB_JOLOKIA_PASSWORD_RANDOM=true \
    AB_JOLOKIA_AUTH_OPENSHIFT=true

# Expose jolokia port
EXPOSE 8778

LABEL name="$FUSE_KARAF_IMAGE_NAME" \
      version="$FUSE_KARAF_IMAGE_VERSION" \
      maintainer="Otavio Piske <opiske@redhat.com>" \
      summary="Platform for building and running Apache Karaf OSGi applications" \
      description="Platform for building and running Apache Karaf OSGi applications" \
      com.redhat.component="fuse-karaf-openshift-container" \
      io.fabric8.s2i.version.maven="3.3.3-1.el7" \
      io.fabric8.s2i.version.jolokia="$JOLOKIA_VERSION" \
      io.fabric8.s2i.version.karaf="$KARAF_FRAMEWORK_VERSION" \
      io.fabric8.s2i.version.prometheus.jmx_exporter="$PROMETHEUS_JMX_EXPORTER_VERSION" \
      io.k8s.description="Platform for building and running Apache Karaf OSGi applications" \
      io.k8s.display-name="Fuse for OpenShift - Karaf based" \
      io.openshift.s2i.scripts-url="image:///usr/local/s2i" \
      io.openshift.s2i.destination="/tmp" \
      io.openshift.tags="builder,karaf" \
      org.jboss.deployments-dir="/deployments/karaf" \
      com.redhat.deployments-dir="/deployments/karaf" \
      com.redhat.dev-mode="JAVA_DEBUG:false" \
      com.redhat.dev-mode.port="JAVA_DEBUG_PORT:5005"

# Temporary switch to root
USER root

# Use /dev/urandom to speed up startups.
RUN echo securerandom.source=file:/dev/urandom >> /usr/lib/jvm/java/jre/lib/security/java.security

# Add jboss user to the root group
RUN usermod -g root -G jboss jboss

# Upgrade glib2 library to fix CVE-2021-27219
RUN yum --disableplugin=subscription-manager update -y glib2

# Install Maven via SCL

RUN yum install -y rh-maven35 \
    && yum clean all \
    && ln -s /opt/rh/rh-maven35/root/bin/mvn /usr/local/bin/mvn

# Prometheus JMX exporter agent
COPY "artifacts/io/prometheus/jmx/jmx_prometheus_javaagent/${PROMETHEUS_JMX_EXPORTER_VERSION}/jmx_prometheus_javaagent-${PROMETHEUS_JMX_EXPORTER_VERSION}.jar" /opt/prometheus/jmx_prometheus_javaagent.jar
RUN mkdir -p /opt/prometheus/etc
COPY prometheus-opts /opt/prometheus/prometheus-opts
COPY prometheus-config.yml /opt/prometheus/prometheus-config.yml
RUN chmod 444 /opt/prometheus/jmx_prometheus_javaagent.jar \
&& chmod 444 /opt/prometheus/prometheus-config.yml \
&& chmod 755 /opt/prometheus/prometheus-opts \
&& chmod 775 /opt/prometheus/etc \
&& chgrp root /opt/prometheus/etc

EXPOSE 9779

# Jolokia agent
RUN mkdir -p /opt/jolokia/etc
COPY "artifacts/org/jolokia/jolokia-jvm/${JOLOKIA_VERSION}/jolokia-jvm-${JOLOKIA_VERSION}-agent.jar" /opt/jolokia/jolokia.jar
ADD jolokia-opts /opt/jolokia/jolokia-opts
RUN chmod 444 /opt/jolokia/jolokia.jar \
 && chmod 755 /opt/jolokia/jolokia-opts \
 && chmod 775 /opt/jolokia/etc \
 && chgrp root /opt/jolokia/etc

EXPOSE 8778


# S2I scripts + README
COPY s2i /usr/local/s2i
RUN chmod 755 /usr/local/s2i/*
ADD README.md /usr/local/s2i/usage.txt

# Copy licenses
RUN mkdir -p /opt/fuse/licenses
COPY licenses.css /opt/fuse/licenses
COPY licenses.xml /opt/fuse/licenses
COPY licenses.html /opt/fuse/licenses
COPY apache_software_license_version_2.0-apache-2.0.txt /opt/fuse/licenses

# Add run script as /opt/run-java/run-java.sh and make it executable
COPY run-java.sh /opt/run-java/
RUN chmod 755 /opt/run-java/run-java.sh

# ===================
# Karaf specific code

# Copy deploy-and-run.sh for standalone images
# Necessary to permit running with a randomised UID
COPY deploy-and-run.sh /deployments/
RUN chmod a+x /deployments/deploy-and-run.sh \
 && chmod a+x /usr/local/s2i/* \
 && chmod -R "g+rwX" /deployments \
 && chown -R jboss:root /deployments \
 && chmod -R "g+rwX" /home/jboss \
 && chown -R jboss:root /home/jboss \
 && chmod 664 /etc/passwd

RUN chmod -R "g+rwX" /home/jboss && chown -R jboss:root /home/jboss

# Enable SCL Maven at the start of a session
RUN echo "source /opt/rh/rh-maven35/enable" >> /etc/bashrc

ENV PATH="/opt/rh/rh-maven35/root/usr/bin:${PATH:-/bin:/usr/bin}"
ENV MANPATH="/opt/rh/rh-maven35/root/usr/share/man:${MANPATH}"
ENV PYTHONPATH="/opt/rh/rh-maven35/root/usr/lib/python2.7/site-packages${PYTHONPATH:+:}${PYTHONPATH:-}"

# S2I requires a numeric, non-0 UID. This is the UID for the jboss user in the base image

USER 185
RUN mkdir -p /home/jboss/.m2
COPY settings.xml /home/jboss/.m2/settings.xml

# Enable SCL Maven at the start of a session
RUN echo "source /opt/rh/rh-maven35/enable" >> ~/.bashrc

CMD ["usage"]
