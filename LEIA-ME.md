# Bolaria Entregas — guia de instalação (100% gratuito)

Um único app Android com dois perfis: **dono (admin)** e **entregador**.
Banco e login: Supabase (plano gratuito). APK compilado de graça no GitHub Actions.

> Este código foi escrito sem poder ser compilado no ambiente de criação.
> Se a primeira compilação der erro, copie o log do GitHub Actions e peça a correção.

---------------------------------------------------------------------
## PARTE 1 — Banco de dados (Supabase)

1. Crie uma conta em https://supabase.com e clique em **New project**.
   Escolha um nome, uma senha forte para o banco (guarde) e a região mais próxima
   (South America - São Paulo).
2. No menu **SQL Editor** > **New query**, cole TODO o conteúdo de `supabase/schema.sql`
   e clique em **Run**. Deve aparecer "Success".
3. Em **Authentication > Users > Add user > Create new user**, crie 2 usuários
   (e-mail + senha), marcando **Auto Confirm User**:
   - o do dono (ex.: dono@exemplo.com)
   - o do entregador (ex.: entregador@exemplo.com)
4. Abra `supabase/criar_perfis.sql`, troque os e-mails pelos que você criou, cole no
   SQL Editor e rode. Isso define quem é admin e quem é entregador.
5. Desligue o cadastro aberto, para ninguém criar conta: em **Authentication**,
   na configuração de provedores/e-mail, desative "Allow new users to sign up"
   (o nome e o lugar do botão podem variar conforme a versão do painel).
6. Anote dois valores em **Project Settings > API**:
   - **Project URL** (https://xxxx.supabase.co)
   - **anon public key** (chave pública; a "service_role" NUNCA deve ser usada)

---------------------------------------------------------------------
## PARTE 2 — Chave de assinatura do app (necessária para atualizações)

Sem uma chave fixa, cada APK compilado teria uma assinatura diferente e o Android
recusaria instalar por cima do anterior.

Precisa do programa `keytool` (vem no Java/JDK ou no Android Studio). Se não tiver,
use o Google Cloud Shell (https://shell.cloud.google.com), que já tem.

    keytool -genkeypair -keystore debug.keystore -storepass android -keypass android \
      -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
      -dname "CN=Bolaria,O=Bolaria,C=BR"

Converta em texto (Linux/Cloud Shell):   base64 -w0 debug.keystore
No Windows (PowerShell):  [Convert]::ToBase64String([IO.File]::ReadAllBytes("debug.keystore"))

Copie o texto gerado (uma linha enorme). **Guarde o arquivo debug.keystore em um
lugar seguro (dois backups).** Se perder, só será possível reinstalar o app do zero.

---------------------------------------------------------------------
## PARTE 3 — GitHub (compila o APK e guarda as versões)

1. Crie conta em https://github.com e um repositório **público** novo
   (ex.: `bolaria-entregas`). Público é necessário para o app baixar atualizações
   sem login. Não há senhas no código; elas ficam nos "Secrets" abaixo.
2. Envie o conteúdo desta pasta para o repositório (inclusive a pasta oculta `.github`).
   Mais fácil: instale o GitHub Desktop, clone o repositório vazio, copie os arquivos
   para dentro e faça "Commit" + "Push". Branch principal: `main`.
3. No repositório: **Settings > Secrets and variables > Actions > New repository secret**.
   Crie 3 segredos:
   - `SUPABASE_URL`       = Project URL (Parte 1, passo 6)
   - `SUPABASE_ANON_KEY`  = anon public key
   - `KEYSTORE_B64`       = o texto base64 da Parte 2
4. Vá em **Actions > Compilar APK**. O push já deve ter iniciado a compilação
   (ou clique em **Run workflow**). Leva alguns minutos.
5. Terminando, abra **Releases** (coluna direita da página do repositório) e baixe
   `bolaria-entregas.apk`.

---------------------------------------------------------------------
## PARTE 4 — Instalar nos celulares

1. Envie o APK (ou o link da Release) para o celular do dono e do entregador.
2. Ao abrir o arquivo, o Android pede para permitir "instalar apps desconhecidos"
   para o app usado (navegador/gerenciador de arquivos). Permita e instale.
3. Entre com o e-mail e a senha de cada um. O papel define a tela.

Primeiro uso do dono:
- Aba **Produtos**: cadastre maria maluca, empada, brownie, combos etc., com preço.
- Aba **Entregas > Nova entrega**: preencha, use + / − nos produtos, escolha dia e
  horário e salve. Depois avise o entregador pelo WhatsApp.
- O entregador abre o app, vê a entrega, toca em **Aceitar** e depois em
  **Marcar como concluída**. O dono vê o status mudar em tempo real.

---------------------------------------------------------------------
## PARTE 5 — Entregar atualizações

1. Altere o código e faça push para `main` (ou rode o workflow manualmente).
2. O GitHub compila e cria uma nova Release (v2, v3...).
3. Ao abrir o app, ele consulta a última Release; se for mais nova, mostra
   "Nova versão disponível". O usuário toca em **Baixar**, abre o arquivo baixado e
   instala por cima. Os dados continuam salvos (ficam no Supabase).

A atualização NÃO é silenciosa: o Android exige o toque em "Instalar".

---------------------------------------------------------------------
## PARTE 6 — Ping diário (evita pausa do projeto gratuito)

O arquivo `.github/workflows/ping-supabase.yml` já faz isso todo dia, usando os
mesmos segredos. Teste em **Actions > Ping Supabase > Run workflow**: deve ficar verde.
Lembre de exportar um backup do banco de vez em quando.

---------------------------------------------------------------------
## Rodar no computador (opcional, para desenvolver)

    flutter create . --platforms=android
    flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
                --dart-define=SUPABASE_ANON_KEY=SUA_CHAVE_ANON

(O comando `flutter create .` pode sobrescrever lib/main.dart e pubspec.yaml; faça
cópia antes e restaure depois.)

## Problemas comuns
- "Invalid login credentials": usuário não criado ou sem "Auto Confirm".
- Tela "perfil não configurado": faltou rodar `criar_perfis.sql` com o e-mail certo.
- Lista não atualiza sozinha: confira se a linha `alter publication supabase_realtime ...`
  do schema.sql rodou. Puxar a lista para baixo também atualiza.
- "App não instalado" ao atualizar: o APK foi assinado com outra chave. Confira o
  segredo `KEYSTORE_B64` (e reinstale uma vez desinstalando o app antigo).
