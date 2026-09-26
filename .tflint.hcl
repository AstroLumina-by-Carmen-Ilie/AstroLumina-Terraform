# TFLint — recommended Terraform rules (libvirt-only stack, no cloud provider presets)
config {
  format = "compact"
  plugin_dir = "~/.tflint.d/plugins"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
