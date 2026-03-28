function print_key(key_info)
   rig.println(key_info)
end

rig.on_key(print_key)

rig.loop()
