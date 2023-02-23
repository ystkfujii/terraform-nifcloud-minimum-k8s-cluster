## 🚀Getting Started🚀

#### 準備

- NIFCLOUDのアカウントを用意する
- `ACCESS_KEY_ID`/`SECRET_ACCESS_KEY`を設定
  ```bash
  export NIFCLOUD_ACCESS_KEY_ID=<YOUR ACCESS KEY>
  export NIFCLOUD_SECRET_ACCESS_KEY=<YOUR SECRET ACCESS KEY>
  ```
- インスタンスに接続する際に使用するSSH KEYを指定
  ```bash
  export TF_VAR_instance_key_name=<YOUR SSH KEY NAME ON NIFCLOUD>
  ```

#### 構築

- terraformの初期化
  ```bash
  terraform init
  ```
- terraformの実行
  ```bash
  export TF_VAR_working_server_ip=$(curl ifconfig.me)
  terraform apply
  ```
- 10~15分ほどまつ

#### 確認

- Control PlaneのIP取得
  ```bash
  CP_IP=$(terraform output -json | jq -r -c '.control_plane_info.value | to_entries[] | .value.public_ip')
  ```
- SSH接続
  ```bash
  ssh -i <YOUR KEY PATH> root@${CP_IP}
  ```
- kubectl実行
  ```bash
  kubectl get node
  kubectl get pod -A
  ```