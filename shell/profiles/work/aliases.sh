# shellcheck shell=bash
# Work-only aliases: Kubernetes and minikube.

alias kc=kubectl
alias kcaMem="kubectl top pods -A --sort-by='memory'"

alias ms='minikube start'
alias mt='minikube tunnel'
alias md='minikube addons enable metrics-server; minikube dashboard'
alias emd='eval $(minikube docker-env)'
alias emdu='eval $(minikube docker-env -u)'
