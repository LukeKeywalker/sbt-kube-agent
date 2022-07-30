FROM jenkins/inbound-agent:latest-jdk11

# Build variables
ARG SCALA_VERSION=2.12.14
ARG SBT_VERSION=1.5.4

# Environment variables
ENV SBT_HOME=/usr/share/sbt

USER root

RUN apt-get update && apt-get -y install apt-utils

# Install and keep a copy of bash.  Some scala/scalac scripts depend on bash(!),
# and work unreliably with ash, et al.
RUN apt-get -y install bash

# Install SBT
#
# There are Windows specific files included in the download that
# we remove to save space and avoid confusion (bin/sbt.bat conf/sbtconfig.txt).
#
# And yep, we do this all in one mega command to keep the layer small. If you
# are working on this in the future, https://github.com/wagoodman/dive is your
# friend.
#
# NOTE: there is currently an experimental sbt pkg for alpine in edge/testing:
#
#     https://git.alpinelinux.org/aports/tree/testing/sbt/APKBUILD.
#
# But we don't want to depend on something outside of the stable alpine
# tracking.
RUN apt-get -y install curl && \
    # Install sbt base
    mkdir -p "${SBT_HOME}" && \
    curl -fsL "https://github.com/sbt/sbt/releases/download/v${SBT_VERSION}/sbt-${SBT_VERSION}.tgz" \
      | tar xfz - --strip-components=1 -C "${SBT_HOME}" && \
    ln -s "${SBT_HOME}"/bin/sbt /usr/local/bin/sbt && \
    mkdir -p "${HOME}"/.sbt && \
    sbt ++"${SCALA_VERSION}" sbtVersion && \
    # Get rid of Windows specific files
    rm "${SBT_HOME}"/bin/sbt.bat && \
    rm "${SBT_HOME}"/conf/sbtconfig.txt 

# Verify SBT is installed successfully.
#
# This step doesn't really do anything, and should be a no-op. Thus it also
# exists somewhat as a debug layer -- if inspection/logs reveal that additional
# file are being automatically installed at this step, then we probably didnt
# successfully fully cache install SBT in the previous step.
RUN sbt sbtVersion

# Define working directory. This is basically just the starting point for usage
# of containers based on this image, so let's have an isolated src directory for
# people to mount their code into, and avoid confusion with $HOME.
WORKDIR /src

# Install Scala
#
# SBT *really* wants to manage Scala itself and will fight you if you try to do
# other ways, so we cave in and let it download a copy of the version we want
# for caching. Unfortunately, it has no command to do this explicitly that we
# could discover, so the only way to make this happen is to create a phantom
# project, compile it, and then delete it afterwards.
#
# (Inspecting this layer reveals some additional .ivy2 cache is also created,
# TODO to figure out more what's actually going on there, but we want to cache
# that anyhow for now. Note even if we were not installing Scala with this step,
# we may have to continue to do this anyhow in the future.)
RUN \
  mkdir project && \
  echo "scalaVersion := \"${SCALA_VERSION}\"" > build.sbt && \
  echo "sbt.version=${SBT_VERSION}" > project/build.properties && \
  echo "case object Temp" > Temp.scala && \
  sbt compile && \
  rm -r project && rm build.sbt && rm Temp.scala && rm -r target

ENTRYPOINT ["/usr/local/bin/jenkins-agent"]
