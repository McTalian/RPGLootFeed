package = "rpglootfeed"
version = "1-1"
source = {
   url = "git+https://github.com/Mctalian-WoW-Addons/RPGLootFeed.git"
}
dependencies = {
   "lua >= 5.3",
   "busted >= 2.2",
   "cluacov >= 1.0",
   "luacov-html >= 1.0"
}
build = {
   type = "builtin",
   modules = {}
}
