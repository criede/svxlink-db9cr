# The name of the module without the Module prefix
set(MODNAME SelCallEnc)

# Install targets
install_mkdir(${SVX_SPOOL_INSTALL_DIR}/propagation_monitor)
install_files_if_not_exists(${SVX_SHARE_INSTALL_DIR}/modules.d Module${MODNAME}.tcl)
install_files_if_not_exists(${SVX_SHARE_INSTALL_DIR}/events.d ${MODNAME}.tcl)
install_if_not_exists(Module${MODNAME}.conf
  ${SVX_SYSCONF_INSTALL_DIR}/svxlink.d
  )
