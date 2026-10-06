# lane-files

Gestor de archivos para [LaneTK](https://github.com/Ansmoun/lanetk). Forma parte del ecosistema del entorno [Lane](https://github.com/Ansmoun/lane) pero es autónomo.

## Requisitos

- LuaJIT
- LaneTK en `/opt/lanetk` o clonado en `~/proyectos/lanetk`
- Servidor X
- `xdg-open` para abrir archivos

## Instalación

```sh
git clone https://github.com/Ansmoun/lane-files.git
cd lane-files
sudo tools/install.sh
```

## Uso

```sh
/opt/lane-files/run app.lua              # abre en $HOME
/opt/lane-files/run app.lua /ruta/ini    # abre en la ruta indicada
```

## Licencia

GPL-3.0. Ver [LICENSE](LICENSE).
