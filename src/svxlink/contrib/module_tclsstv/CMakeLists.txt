# The name of the module without the Module prefix
set(MODNAME TclSSTV)

# Install targets
install(FILES go_sstv.py DESTINATION ${BIN_INSTALL_DIR})
install_files_if_not_exists(${SVX_SHARE_INSTALL_DIR}/modules.d Module${MODNAME}.tcl)
install_if_not_exists(Module${MODNAME}.conf
  ${SVX_SYSCONF_INSTALL_DIR}/svxlink.d
  )
