# Public Bash Script

One-line install scripts for common CLI tools and services. Designed for manual use, automation pipelines (e.g. Jenkins), and heterogeneous environments (Debian, Alpine, Proxmox, macOS, and others).

---

## Supported Platforms

| Platform    | Scope                          | Notes                                    |
| ----------- | ------------------------------ | ---------------------------------------- |
| **Bash**    | All scripts                    | Primary usage; one-liners and local runs |
| **Jenkins** | Pipeline steps, agents, Docker | Use in `bash` steps or in Dockerfile     |

## Quick Start

Run an installer directly from the repository (replace `<script-name>.sh` with the script you need):

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/zenkiet/public-bash-script/main/bash/<script-name>.sh)"
```

---

## Available Scripts

| Script         | Description                                                                        |
| -------------- | ---------------------------------------------------------------------------------- |
| **lazydocker** | Install [lazydocker](https://github.com/jesseduffield/lazydocker) (TUI for Docker) |

### Lazydocker

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/zenkiet/public-bash-script/main/bash/lazydocker.sh)"
```

---

## Using in Jenkins

Use the same one-liner inside a Jenkins pipeline or on an agent:

```groovy
pipeline {
    agent any
    stages {
        stage('Install tools') {
            steps {
                sh 'bash -c "$(curl -fsSL https://raw.githubusercontent.com/zenkiet/public-bash-script/main/bash/lazydocker.sh)"'
            }
        }
    }
}
```

Or from a Jenkinsfile scripted syntax:

```groovy
node {
    sh 'bash -c "$(curl -fsSL https://raw.githubusercontent.com/zenkiet/public-bash-script/main/bash/lazydocker.sh)"'
}
```

## 🤝 Contributing

Contributions are welcome! Please open issues or pull requests for bug fixes, features, or improvements.

## 📄 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

---

<div align="center">

### **If this project helped you, please consider supporting its development**

<div>⭐ Star the repository ⭐</div>
<div>📢 Share it with your network 📢</div>

<sub>Made with ❤️ by <a href="https://github.com/zenkiet">ZenKiet</a></sub>

</div>
