# lua-reverse-proxy
LuaでFQDNをもとに動的にホストとポートを振り分けするリバースプロキシ実装のサンプル。
OpenRestyでの動作を前提にしています。

# Middlewear
- MySQL@8.0
- Memcached@1.6.9

# Module used
- resty.mysql
- resty.memcached
- resty.ipmatcher
- cjson

## Details
 See: https://wp.laziness.ga/archives/724
