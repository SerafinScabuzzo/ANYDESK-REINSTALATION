# ANYDESK REINSTALATION

Programa para Windows que desinstala AnyDesk por completo, lo vuelve a instalar y le pone una contraseña nueva. Al terminar deja AnyDesk abierto y crea un archivo de texto en el escritorio con el código de vinculación y la contraseña.

Sirve cuando AnyDesk queda en mal estado y conviene empezar de cero. El código anterior deja de servir, porque se borra toda la configuración guardada.

## Qué tiene que haber en la carpeta

Estos archivos, juntos:

- `Reinstalar-AnyDesk.bat`: es el programa. Se abre con doble clic.
- `Reinstalar-AnyDesk.ps1`: hace la desinstalación, el borrado y la instalación.
- El instalador de AnyDesk, con un nombre que empiece por `AnyDesk` y termine en `.exe`. Por ejemplo `AnyDesk (1).exe`.

El instalador no está en este repositorio. Hay que copiarlo a la misma carpeta antes de ejecutar el programa. Si no está, el programa avisa y no cambia nada.

## Cómo se usa

1. Doble clic en `Reinstalar-AnyDesk.bat`.
2. Aceptar el permiso de administrador de Windows.
3. Escribir la contraseña nueva y repetirla.
4. Escribir `S` para confirmar.

Si no se escribe `S`, el programa se cancela y AnyDesk queda como estaba.

La contraseña tiene que tener al menos 8 caracteres. Sirven letras, números y símbolos simples. No sirven la eñe ni las letras con acento, porque al guardarla se usa texto simple.

Mientras se escribe, la contraseña no se ve en la ventana.

## Qué hace, en orden

1. Muestra el código actual, si AnyDesk ya está instalado.
2. Cierra AnyDesk y detiene su servicio.
3. Lo desinstala.
4. Borra lo que haya quedado guardado:
   - la carpeta de instalación;
   - la configuración del servicio, en `C:\ProgramData\AnyDesk`;
   - la configuración de cada usuario, en `AppData\Roaming\AnyDesk` y `AppData\Local\AnyDesk`;
   - las claves de AnyDesk en el registro de Windows.
5. Instala de nuevo en `C:\Program Files (x86)\AnyDesk`, con inicio junto con Windows, acceso directo e icono en el escritorio.
6. Inicia el servicio y aplica la contraseña de acceso desatendido.
7. Abre AnyDesk y espera el código de vinculación nuevo.
8. Deja AnyDesk abierto.

La contraseña queda como clave de acceso desatendido: con el código nuevo y esa clave se puede entrar a esa PC sin que alguien acepte la conexión en el momento.

## El archivo del escritorio

Al terminar crea `AnyDesk-acceso.txt` en el escritorio. Contiene:

- la fecha;
- el código de vinculación nuevo;
- la contraseña.

La contraseña queda escrita en texto plano. Cualquier persona que use esa PC puede abrir el archivo y leerla.

Si el código tarda en aparecer, el txt lo dice. AnyDesk queda abierto para copiar el número desde su ventana. Hace falta Internet para que AnyDesk obtenga el código.

Si la contraseña no se puede confirmar dentro de AnyDesk, el programa también lo avisa. En ese caso hay que cargarla a mano en AnyDesk, en Seguridad, Acceso desatendido.

## Qué conviene tener en cuenta

- El código viejo deja de funcionar en cuanto el borrado termina.
- Conviene ejecutarlo cuando nadie necesite conectarse a esa PC con el código actual.
- Hace falta permiso de administrador.
- Si Windows no puede borrar alguna carpeta o deja el servicio a medias, el programa se detiene y pide reiniciar la PC para ejecutarlo otra vez.
