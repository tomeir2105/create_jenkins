#####################################
### Script created by Meir
### Script creates a Jenkins docker and 3 agents with sshd, Java and Python.
### Script Creates ssh keys and copies them to the jenkins machine and the agents
### All agents have the same private key.
### Don't forget to use "Manualy trusted key verification strategy" in the ssh settings and put the private key in the user profile
#####################################

#!/bin/bash
set -e

AGENTS=("agent1" "agent2" "agent3")
DOCKERFILE_CONTENT='FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

RUN echo '\''Acquire::Check-Valid-Until "false";'\'' | tee /etc/apt/apt.conf.d/99no-check-valid-until \
    && apt-get update \
    && apt-get install -y openssh-server sudo openjdk-17-jdk python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /run/sshd

RUN useradd -m -s /bin/bash jenkins \
    && useradd -m -s /bin/bash user \
    && echo "jenkins ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
    && echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

RUN mkdir -p /home/jenkins/.ssh && chown jenkins:jenkins /home/jenkins/.ssh && chmod 700 /home/jenkins/.ssh \
    && mkdir -p /home/user/.ssh && chown user:user /home/user/.ssh && chmod 700 /home/user/.ssh

ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV PATH="$JAVA_HOME/bin:$PATH"

EXPOSE 22

CMD ["/usr/sbin/sshd", "-D"]
'

for agent in "${AGENTS[@]}"; do
  echo "Creating folder: $agent"
  mkdir -p "$agent"
  echo "Writing Dockerfile in $agent"
  echo "$DOCKERFILE_CONTENT" > "$agent/Dockerfile"
done

echo "All agent folders and Dockerfiles created."


#########################
# st0_clean.sh
#########################
echo "WARNING: This will STOP and REMOVE all containers, volumes, networks, and agent data."
read -p "Are you sure you want to continue? (yes/[no]): " confirm

if [[ "$confirm" != "yes" ]]; then
  echo "Aborted."
  exit 1
fi

echo "Cleaning docker environments..."

echo -e "\n=== STAGE 0: Remove All Docker Containers, Images, Volumes, and Networks ==="
if [ "$(docker ps -q)" ]; then docker stop $(docker ps -q); fi
if [ "$(docker ps -a -q)" ]; then docker rm -f $(docker ps -a -q); fi
if [ "$(docker images -q)" ]; then docker rmi -f $(docker images -q); fi
if [ "$(docker volume ls -q)" ]; then docker volume rm -f $(docker volume ls -q); fi
if [ "$(docker network ls --filter 'name!=bridge' --filter 'name!=host' --filter 'name!=none' -q)" ]; then
  docker network rm $(docker network ls --filter 'name!=bridge' --filter 'name!=host' --filter 'name!=none' -q)
fi
if docker network ls --format '{{.Name}}' | grep -q '^jenkins-net$'; then
  docker network rm jenkins-net
fi
docker builder prune -a -f
echo "Docker cleanup complete."


#########################
# st1_jenkins.sh
#########################
echo -e "\n=== STAGE 1: Jenkins Master Setup ==="

if ! command -v docker &>/dev/null; then
  echo "Docker is not installed. Please install Docker first."
  exit 1
fi

if ! docker network ls --format '{{.Name}}' | grep -q '^jenkins-net$'; then
  docker network create jenkins-net
else
  echo "Docker network 'jenkins-net' already exists."
fi

docker pull jenkins/jenkins:lts

if docker ps -a --format '{{.Names}}' | grep -Eq '^jenkins$'; then
  docker stop jenkins
  docker rm jenkins
fi

docker run -d --name jenkins --network jenkins-net \
  -p 8080:8080 -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --user root \
  jenkins/jenkins:lts

echo "Waiting for Jenkins to initialize..."
for i in {1..20}; do
  if docker exec jenkins test -f /var/jenkins_home/secrets/initialAdminPassword; then
    echo "Initial Jenkins admin password:"
    docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
    break
  fi
  sleep 3
done


#########################
# st2_agents.sh
#########################
echo -e "\n=== STAGE 2: Create Jenkins Agents ==="

for index in "${!AGENTS[@]}"; do
  agent="${AGENTS[$index]}"
  IMAGE_NAME="jenkins-$agent-image"
  CONTAINER_NAME="jenkins-$agent"
  AGENT_DIR="./$agent"
  SSH_DIR="$AGENT_DIR/.ssh"

  AGENT_NUMBER=$(echo "$agent" | grep -o '[0-9]\+')
  if ! [[ "$AGENT_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "Invalid agent name '$agent'. Must contain a number." >&2
    exit 1
  fi

  PORT=$((2220 + 10#$AGENT_NUMBER))
  VOLUME_NAME="jenkins-${agent}-vol"

  mkdir -p "$SSH_DIR"

  if [[ ! -f "$SSH_DIR/id_rsa" ]]; then
    ssh-keygen -t rsa -b 4096 -f "$SSH_DIR/id_rsa" -N ""
    chmod 600 "$SSH_DIR/id_rsa"
    chmod 644 "$SSH_DIR/id_rsa.pub"
    chmod 700 "$SSH_DIR"
  fi

  if [[ ! -f "$AGENT_DIR/Dockerfile" ]]; then
    echo "Dockerfile missing in $AGENT_DIR — skipping $agent."
    continue
  fi

  if docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then
    docker rm -f "$CONTAINER_NAME"
  fi

  if docker volume ls --format '{{.Name}}' | grep -Eq "^${VOLUME_NAME}$"; then
    docker volume rm "$VOLUME_NAME"
  fi

  docker volume create "$VOLUME_NAME"

  docker build --no-cache -t "$IMAGE_NAME" "$AGENT_DIR" || {
    echo "Failed to build image for $agent."
    continue
  }

  docker run -d --name "$CONTAINER_NAME" --network jenkins-net \
    -v "$SSH_DIR/id_rsa.pub:/home/jenkins/.ssh/authorized_keys" \
    -v "$VOLUME_NAME:/data" \
    -p "$PORT:22" "$IMAGE_NAME"
done


#########################
# st3_ssh.sh
#########################
echo -e "\n=== STAGE 3: Configure Jenkins Master to Connect to Agents ==="

JENKINS_CONTAINER="jenkins"
SSH_DIR="./agent1/.ssh"
PUB_KEY_CONTENT=$(<"$SSH_DIR/id_rsa.pub")

if [[ ! -r "$SSH_DIR/id_rsa" || ! -r "$SSH_DIR/id_rsa.pub" ]]; then
  echo "SSH keys not found in $SSH_DIR"
  exit 1
fi

docker exec "$JENKINS_CONTAINER" mkdir -p /var/jenkins_home/.ssh
docker cp "$SSH_DIR/id_rsa" "$JENKINS_CONTAINER:/var/jenkins_home/.ssh/id_rsa"
docker cp "$SSH_DIR/id_rsa.pub" "$JENKINS_CONTAINER:/var/jenkins_home/.ssh/id_rsa.pub"

docker exec "$JENKINS_CONTAINER" bash -c "
  chmod 600 /var/jenkins_home/.ssh/id_rsa &&
  chmod 644 /var/jenkins_home/.ssh/id_rsa.pub &&
  touch /var/jenkins_home/.ssh/known_hosts &&
  chown -R jenkins:jenkins /var/jenkins_home/.ssh
"

for agent in "${AGENTS[@]}"; do
  CONTAINER_NAME="jenkins-$agent"
  HOSTNAME="$CONTAINER_NAME"

  docker exec "$JENKINS_CONTAINER" bash -c "
    ssh-keygen -f /var/jenkins_home/.ssh/known_hosts -R $HOSTNAME 2>/dev/null || true
  "

  docker exec "$JENKINS_CONTAINER" bash -c "
    ssh-keyscan -p 22 -H $HOSTNAME >> /var/jenkins_home/.ssh/known_hosts &&
    chown jenkins:jenkins /var/jenkins_home/.ssh/known_hosts &&
    chmod 644 /var/jenkins_home/.ssh/known_hosts
  "

  docker exec "$CONTAINER_NAME" bash -c "
    mkdir -p /home/jenkins/.ssh &&
    touch /home/jenkins/.ssh/authorized_keys &&
    grep -qxF '$PUB_KEY_CONTENT' /home/jenkins/.ssh/authorized_keys || echo '$PUB_KEY_CONTENT' >> /home/jenkins/.ssh/authorized_keys &&
    chown -R jenkins:jenkins /home/jenkins/.ssh &&
    chmod 700 /home/jenkins/.ssh &&
    chmod 600 /home/jenkins/.ssh/authorized_keys
  "

  docker exec "$JENKINS_CONTAINER" ssh -i /var/jenkins_home/.ssh/id_rsa \
    -o StrictHostKeyChecking=no -o BatchMode=yes \
    -p 22 jenkins@"$HOSTNAME" echo "SSH to $agent successful" || echo "SSH to $agent ($HOSTNAME) failed"
done


#########################
# st4_connect.sh
#########################
echo -e "\n=== STAGE 4: Verify Jenkins Master Can SSH to Agents ==="

for agent in "${AGENTS[@]}"; do
  CONTAINER_NAME="jenkins-$agent"
  agent_ip=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER_NAME")
  echo "IP of $agent: $agent_ip"

  docker exec "$JENKINS_CONTAINER" bash -c "
    ssh-keygen -f /root/.ssh/known_hosts -R $agent_ip 2>/dev/null || true
  "

  docker exec "$JENKINS_CONTAINER" bash -c "
    ssh -i /var/jenkins_home/.ssh/id_rsa \
        -o StrictHostKeyChecking=no -o BatchMode=yes \
        jenkins@$agent_ip \
        'echo SSH to $agent at $agent_ip successful'
  " || {
    echo "SSH to $agent ($agent_ip) failed"
    docker exec "$JENKINS_CONTAINER" ls -la /var/jenkins_home/.ssh
    docker exec "$JENKINS_CONTAINER" whoami
  }

  echo ""
done


#########################
# st5_keys.sh
#########################
echo -e "\n=== STAGE 5: Display SSH Keys for Jenkins Agent Access ==="

SSH_KEY_PATH="./agent1/.ssh/id_rsa"
PUB_KEY_PATH="./agent1/.ssh/id_rsa.pub"

echo -e "\nKeys belong to user: jenkins"

echo -e "\nPrivate Key:"
cat "$SSH_KEY_PATH"

echo -e "\nPublic Key:"
cat "$PUB_KEY_PATH"

for agent in "${AGENTS[@]}"; do
  CONTAINER_NAME="jenkins-$agent"
  agent_ip=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER_NAME")
  echo -e "\nAgent: $agent"
  echo "IP: $agent_ip"
done

echo -e "\nJenkins Initial Admin Password:"
docker exec "$JENKINS_CONTAINER" cat /var/jenkins_home/secrets/initialAdminPassword || echo "Could not retrieve admin password"
