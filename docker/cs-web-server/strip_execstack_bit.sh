#Clear the flag on the core (and, while you’re here, on all AMXX modules):
# Core
execstack -c mnt/addons/amxmodx/dlls/amxmodx_mm_i386.so

# Recommended: fix every AMXX module too
find mnt/addons/amxmodx -type f -name '*.so' -exec execstack -c {} +

