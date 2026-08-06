# Shane's public identity, single-sourced. These values were previously copy-pasted
# across every host assembly (the SSH public key appeared seven times). All of it is
# deliberately public: the SSH key is the 1Password-held public half, used both for
# sshd authorized_keys and git commit signing. The private work repo does NOT consume
# this — it supplies its own identity via publicHome.git.* (see README).
{
  username = "shane";
  userName = "Shane Murphy";
  userEmail = "mail@semurphy.com";
  sshPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBwRBMnr95gqzkvJHmNDCprKK2QcV2vNQVS6mAsGzcz3";
}
