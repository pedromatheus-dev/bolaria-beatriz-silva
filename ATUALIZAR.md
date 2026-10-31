# Como atualizar para a versão 4

1. SUPABASE: SQL Editor > New query > cole supabase/migracao_v4.sql > Run.
   (Faça isso ANTES de enviar o código novo. A migracao_v2.sql já deve ter sido rodada.)
2. Copie os arquivos do zip para a pasta do projeto (a que tem a pasta oculta .git),
   substituindo os antigos. Mostre os itens ocultos para ver a pasta .github.
   Seu assets/icon.png continua lá (o zip não o inclui).
3. GitHub: Settings > Pages > Source: "Deploy from a branch" > Branch: main, pasta /docs > Save.
   (Cria o link clicável que abre a entrega no app. Leva ~1 minuto para ficar no ar.)
4. PowerShell na pasta do projeto:
      git add .
      git commit -m "Versão 4"
      git push
5. GitHub > Actions > "Compilar APK": espere o ✔ verde.
6. Celulares: abra o app > "Nova versão disponível" > Baixar > abrir o arquivo > Instalar.
7. No app, aba "Entregador": cadastre nome e telefone do entregador.
   Aba "Meus dados": cadastre seu nome e telefone (e confira a taxa de entrega).
   Aba Produtos: cadastre Empada e recrie os combos em Produtos > Combos > Novo combo.
