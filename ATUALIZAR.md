# Como atualizar o app (versão 2 em diante)

1. SUPABASE: SQL Editor > New query > cole o conteúdo de supabase/migracao_v2.sql > Run.
   (Faça isso ANTES de enviar o código novo.)
2. Copie os arquivos novos para a pasta do projeto no seu computador (a pasta que já
   tem a pasta oculta .git), substituindo os antigos.
   No Explorador: Exibir > Mostrar > Itens ocultos (para ver a pasta .github).
3. Logo do app: coloque a imagem em assets/icon.png (PNG quadrado, ideal 1024x1024).
4. PowerShell na pasta do projeto:
      git add .
      git commit -m "Versão 2"
      git push
5. GitHub > Actions > "Compilar APK": espere o ✔ verde (5 a 10 min).
6. Celulares: abra o app > "Nova versão disponível" > Baixar > abrir o arquivo > Instalar.
