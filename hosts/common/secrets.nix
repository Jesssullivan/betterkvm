_:
{
  sops = {
    defaultSopsFile = ../../secrets/pikvm.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      tailscale-auth-key = {
        key = "tailscale_authkey";
        restartUnits = [ "tailscaled.service" ];
      };
      nut-password = {
        key = "kvmd_admin_password";
        owner = "nut";
        group = "nut";
      };
    };
  };
}
