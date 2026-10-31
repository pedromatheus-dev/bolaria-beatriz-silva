"""Ajusta o AndroidManifest gerado pelo `flutter create`:
- permissão de internet
- nome do app
- link bolaria://entrega/<id> (abre a entrega a partir do WhatsApp)
"""
import re

p = 'android/app/src/main/AndroidManifest.xml'
s = open(p, encoding='utf-8').read()

if 'permission.INTERNET' not in s:
    s = s.replace('<application',
                  '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)

s = re.sub(r'android:label="[^"]*"', 'android:label="Bolaria Beatriz"', s, count=1)

if 'android:scheme="bolaria"' not in s:
    filtro = '''
            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="bolaria" android:host="entrega"/>
            </intent-filter>
            <meta-data android:name="flutter_deeplinking_enabled" android:value="false"/>
        '''
    s = s.replace('</activity>', filtro + '</activity>', 1)

open(p, 'w', encoding='utf-8').write(s)
print('AndroidManifest ajustado')
