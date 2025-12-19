fx_version 'cerulean'
game 'gta5'

lua54 'yes'

dependency 'mythic-base'
dependency 'xsound'


shared_scripts {
    'shared/config.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}