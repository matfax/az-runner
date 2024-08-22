FROM matfax.azurecr.io/ubuntu:focal as cache1

FROM matfax.azurecr.io/github-runner-base:ubuntu-focal as cache2

FROM matfax.azurecr.io/github-runner:2.319.1
