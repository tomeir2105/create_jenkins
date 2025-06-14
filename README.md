# Jenkins Master and SSH Agents Setup

This project automates the creation and setup of a Jenkins master container and three agent containers using Docker. The agents support SSH access, Java, and Python environments.

# Notes
- **During setup, all Docker containers, volumes, and images will be deleted**.
- After script finishes, create the Nodes in Jenkins
- use /home/jenkins as the Remote root directory.
- use the agent IP as printed in the script.
- Add the PRIVATE KEY (printed when the script ends) to the user profile.
- Select "Manually trusted key verification strategy" in Jenkins SSH settings and add the generated private key from `./agent1/.ssh/id_rsa`.
- update the ssh-slaves plugin from jenkins-cli (see instructions down here)

## Update ssh-slaves
- Create a Jenkins user Token
- Download the cli agent from jenkins - wget http://localhost:8080/jnlpJars/jenkins-cli.jar
- Install the plugin - java -jar jenkins-cli.jar -s http://localhost:8080/   -auth jenkins:[Token]  install-plugin ssh-slaves:3.1031.v72c6b_883b_869

## Features

- Jenkins master with persistent volume
- 3 Ubuntu-based Jenkins agents with:
  - OpenSSH server
  - OpenJDK 17
  - Python 3 and pip
- Automatic SSH key generation and distribution
- Shared SSH key for all agents
- Full Docker cleanup before setup
- Agent port mapping (agent1: 2221, agent2: 2222, agent3: 2223)

## Requirements

- Docker installed
- Bash shell

## Usage

```bash
chmod +x setup_jenkins_agents.sh
./setup_jenkins_agents.sh
```

## Stages

1. Cleanup Docker
2. Start Jenkins master
3. Build and run agents
4. Configure SSH access
5. Verify Jenkins can SSH into agents
6. Display SSH credentials
