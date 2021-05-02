#!/bin/bash

set -ue

# 処理が成功した時のみexit_statusをsuccessに変更する
exit_status=error
trap finaly EXIT

finaly() {
  # ステージング,本番ならDB削除
  if [ "$APP_ENV" = "staging" -o "$APP_ENV" = "production" ]; then
    delete_db_instance
  fi

  # 生成したconfigファイルを削除
  if [ "$APP_ENV" = "development" ]; then
    for file in `ls config/*.yml.liquid`; do
      rm "$file"
    done
  fi

  # 終了ログを出力
  echo "END $exit_status $0 env: $APP_ENV"
}

restore_db_instance_from_snapshot() {
  # コマンドの出力を他のコマンドの引数に使用すると終了ステータスは無視されてしまう
  # localコマンドと変数への代入を分けることでエラーを無視させないようにできる
  local snapshot_identifier
  snapshot_identifier=`find_latest_snapshot_identifier`

  echo "[start]restore db instance $DB_INSTANCE_IDENTIFIER from snapshot $snapshot_identifier"

  local security_group_id
  security_group_id=`find_security_group_id`

  aws rds restore-db-instance-from-db-snapshot \
    --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" \
    --db-snapshot-identifier "$snapshot_identifier" \
    --vpc-security-group-ids "$security_group_id" \
    --no-publicly-accessible

  echo "[end]restore db instance $DB_INSTANCE_IDENTIFIER from snapshot $snapshot_identifier"
}

find_latest_snapshot_identifier() {
  local snapshot_type="automated"

  local identifier
  identifier=`aws rds describe-db-snapshots \
    --db-instance-identifier $HOGE_DB_INSTANCE_IDENTIFIER \
    --snapshot-type $snapshot_type \
    --query 'reverse(sort_by(DBSnapshots,&InstanceCreateTime))[0].DBSnapshotIdentifier'`
  echo "$identifier" | sed 's/"//g'
}

find_security_group_id() {
  local security_group_id
  security_group_id=`aws ec2 describe-security-groups \
    --group-names $RDS_SECURITY_GROUP_NAME \
    --query SecurityGroups[0].GroupId`
  echo "$security_group_id" | sed 's/"//g'
}

wait_db_instance_available() {
  echo "[start]wait db instance $DB_INSTANCE_IDENTIFIER available"
  aws rds wait db-instance-available --db-instance-identifier "$DB_INSTANCE_IDENTIFIER"
  echo "[end]wait db instance $DB_INSTANCE_IDENTIFIER available"
}

execute_embulk() {
  for file in `ls config/*.yml.liquid`; do
    echo "[start]$file"
    embulk run "$file"
    echo "[end]$file"
  done
}

preview_embulk() {
  for file in `ls config/*.yml.liquid`; do
    echo "[start]preview $file"
    embulk preview "$file"
    echo "[end]preview $file"
  done
}

delete_db_instance() {
  echo "[start]delete db instance $DB_INSTANCE_IDENTIFIER"

  aws rds delete-db-instance \
    --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" \
    --skip-final-snapshot

  echo "[end]delete db instance $DB_INSTANCE_IDENTIFIER"
}

generate_config_file_from_bigquery_schemas() {
  for file in `ls bigquery_schemas/*.json`; do
    # biguqueryのschemaファイルのカラム名を用いて、mysqlから取得するカラムの文字列を生成している
    local json_data
    json_data=`cat $file`
    local len
    len=`echo $json_data | jq length`
    local select_columns=""
    for i in `seq 0 $(($len - 1))`; do
      local row
      row=`echo $json_data | jq .[$i].name`
      local select_columns
      select_columns="$select_columns",`echo $row | sed 's/"//g'`
    done
    # for1週目の,が先頭に入っているので除く
    local select_columns=${select_columns#,}

    # テーブル名とカラム名を置換
    local table_name
    table_name=`basename "$file" .json`
    local config_template=config/template/mysql2bigquery.yml.liquid
    sed -e "s/{{ select_columns }}/"${select_columns}"/g" -e "s/{{ table_name }}/$table_name/g" "$config_template" > config/"$table_name".yml.liquid
  done
}

# main
echo "START $0 env: $APP_ENV"

if [ ! "$APP_ENV" = "development" -a ! "$APP_ENV" = "staging" -a ! "$APP_ENV" = "production" ]; then
  echo "【error】引数に環境名を指定してください(development, staging, production)"
  exit 1
fi

if [ "$APP_ENV" = "development" ]; then
  generate_config_file_from_bigquery_schemas
  preview_embulk
  exit_status=success
elif [ "$APP_ENV" = "staging" -o "$APP_ENV" = "production" ]; then
  generate_config_file_from_bigquery_schemas
  restore_db_instance_from_snapshot
  wait_db_instance_available
  execute_embulk

  exit_status=success
fi
