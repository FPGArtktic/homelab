# GitLab Omnibus config, mounted read-only into the gitlab container.
# Served through the homelab nginx on host :80 (http://gitlab.local). Runners and CI
# job containers reach GitLab directly at gitlab.local -> 10.90.0.20 on :80.

external_url 'http://gitlab.local'
nginx['listen_port'] = 80
nginx['listen_https'] = false

# SSH clones: advertised port on the host.
gitlab_rails['gitlab_shell_ssh_port'] = 2222

# Built-in container registry, served by GitLab's nginx on the published port.
registry_external_url 'http://gitlab.local:5050'
registry_nginx['listen_port'] = 5050
registry_nginx['listen_https'] = false

# Homelab-sized: no Prometheus, few workers.
prometheus_monitoring['enable'] = false
puma['worker_processes'] = 2
sidekiq['max_concurrency'] = 5
gitlab_rails['gitlab_email_enabled'] = false
