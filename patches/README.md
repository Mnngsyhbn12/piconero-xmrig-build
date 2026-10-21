# No patches

Upstream XMRig v6.26.0 (commit b2ca72480c58d197e18c885d9fc1a0c8d517e60a) is used byte-for-byte unchanged.
The build avoids source edits by using linker stubs and CMake options instead;
see ../README.md, section "The deliberate deviations".
If a Piconero build ever edits XMRig, the `.patch` file belongs here, and the
README deviation table plus `sourceModified` in ../xmrig-build-info.json must
change in the same commit.
