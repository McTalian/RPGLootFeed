package = "rpglootfeed"
version = "1-1"
source = {
   url = "https://github.com/Mctalian-WoW-Addons/RPGLootFeed.git"
}
dependencies = {
   "lua >= 5.3",
   "busted >= 2.2",
   "luacov >= 0.15",
   "luacov-html >= 1.0"
}
build = {
   type = "builtin",
   modules = {}
}
