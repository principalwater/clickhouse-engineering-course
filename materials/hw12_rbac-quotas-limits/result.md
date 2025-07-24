## 1. Создание пользователя jhon
```sql
CREATE USER IF NOT EXISTS jhon ON CLUSTER dwh_test IDENTIFIED BY 'qwerty';
```

## 2. Создание роли devs и выдача прав
```sql
CREATE ROLE IF NOT EXISTS devs ON CLUSTER dwh_test;
GRANT SELECT ON system.parts TO devs ON CLUSTER dwh_test;
```

## 3. Назначение роли пользователю
```sql
GRANT devs TO jhon ON CLUSTER dwh_test;
```

## 4. Результаты проверок
### system.role_grants
```
Row 1:
──────
user_name:               jhon
role_name:               ᴺᵁᴸᴸ
granted_role_name:       devs
granted_role_id:         3547a0e2-64aa-506d-7f62-dac7b71623a8
granted_role_is_default: 1
with_admin_option:       0
```
### system.grants
```
Row 1:
──────
user_name:         ᴺᵁᴸᴸ
role_name:         devs
access_type:       SELECT
database:          system
table:             parts
column:            ᴺᵁᴸᴸ
is_partial_revoke: 0
grant_option:      0
```
