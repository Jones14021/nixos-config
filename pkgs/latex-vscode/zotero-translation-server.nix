{
  dockerTools,
}:

dockerTools.pullImage {
  imageName = "jones14021/translation-server";
  imageDigest = "sha256:b02486c54ca50a5e42c3b8fac91b5ad2a2c75d088cc8694dfedaf7cfc452fc50";
  sha256 = "0000000000000000000000000000000000000000000000000000";
  finalImageName = "jones14021/translation-server";
  finalImageTag = "latest";
}
