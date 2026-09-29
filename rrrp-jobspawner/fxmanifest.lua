fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qbx-jobspawner'
author 'Staticx66'
description 'vehicle spawner - no vMenu required'
version '1.0.5'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js'
}

dependencies {
    'ox_lib',
    'qbx_core'
}
