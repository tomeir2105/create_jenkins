# Jenkins Master and SSH Agents Setup

This project automates the creation and setup of a Jenkins master container and three agent containers using Docker. The agents support SSH access, Java, and Python environments.

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

## Notes

- During setup, all Docker containers, volumes, and images will be deleted.
- Use "Manually trusted key verification strategy" in Jenkins SSH settings and add the generated private key from `./agent1/.ssh/id_rsa`.

## Stages

1. Cleanup Docker
2. Start Jenkins master
3. Build and run agents
4. Configure SSH access
5. Verify Jenkins can SSH into agents
6. Display SSH credentials
