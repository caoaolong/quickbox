# Supabase（口令码同步）

1. 打开 Supabase 控制台 → **SQL Editor**，新建查询。
2. 将本目录 `migrations/202605160001_cloud_sync_preset.sql` **全文复制粘贴**后执行一次。
3. 若客户端仍提示找不到函数（schema cache），在同一编辑器再执行一行：
   ```sql
   NOTIFY pgrst, 'reload schema';
   ```
4. 可选自检（同一编辑器）：
   ```sql
   select proname, proargnames from pg_proc where proname = 'publish_cloud_sync_preset';
   ```
