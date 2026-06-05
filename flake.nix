{
  description = "auto-acronym generator for nushell";

  outputs =
    { self }:
    {
      nixosModules.default = import ./module.nix;
      nixosModules.autonym = self.nixosModules.default;
    };
}
