# Gera o icone 1024x1024 do DSH a partir da paleta do app.
# Fundo escuro do tema escuro (0E1013) com degrade sutil, acento ambar (E3A33C)
# desenhando o sinal de prompt (chevron) e o cursor de terminal.
# Saida: Recursos\Assets.xcassets\AppIcon.appiconset\icone-1024.png

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$destino = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Recursos\Assets.xcassets\AppIcon.appiconset'
New-Item -ItemType Directory -Force -Path $destino | Out-Null
$arquivo = Join-Path $destino 'icone-1024.png'

$lado = 1024
$bmp = New-Object System.Drawing.Bitmap $lado, $lado
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

# Fundo: degrade vertical curto, de 171B21 no topo para 0A0C0F na base.
$topo = [System.Drawing.Color]::FromArgb(255, 0x17, 0x1B, 0x21)
$base = [System.Drawing.Color]::FromArgb(255, 0x0A, 0x0C, 0x0F)
$gradiente = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.Point 0, 0),
    (New-Object System.Drawing.Point 0, $lado),
    $topo, $base)
$g.FillRectangle($gradiente, 0, 0, $lado, $lado)
$gradiente.Dispose()

$ambar = [System.Drawing.Color]::FromArgb(255, 0xE3, 0xA3, 0x3C)
$caneta = New-Object System.Drawing.Pen $ambar, 86
$caneta.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$caneta.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$caneta.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round

# Chevron: ponta do prompt. Grupo centralizado em x=512, de y=318 a y=706.
$g.DrawLine($caneta, 312, 270, 547, 512)
$g.DrawLine($caneta, 547, 512, 312, 754)

# Cursor: barra cheia a direita do chevron, com a base na mesma altura da ponta
# de baixo do chevron, como no terminal.
$cursor = New-Object System.Drawing.Rectangle 622, 590, 140, 164
$raio = 32
$caminho = New-Object System.Drawing.Drawing2D.GraphicsPath
$caminho.AddArc(622, 590, $raio * 2, $raio * 2, 180, 90)
$caminho.AddArc(622 + 140 - $raio * 2, 590, $raio * 2, $raio * 2, 270, 90)
$caminho.AddArc(622 + 140 - $raio * 2, 590 + 164 - $raio * 2, $raio * 2, $raio * 2, 0, 90)
$caminho.AddArc(622, 590 + 164 - $raio * 2, $raio * 2, $raio * 2, 90, 90)
$caminho.CloseFigure()
$pincel = New-Object System.Drawing.SolidBrush $ambar
$g.FillPath($pincel, $caminho)
$pincel.Dispose()
$caminho.Dispose()
$caneta.Dispose()

$g.Dispose()
$bmp.Save($arquivo, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

$info = Get-Item $arquivo
"salvo: {0} ({1} bytes)" -f $info.FullName, $info.Length
$medida = [System.Drawing.Image]::FromFile($arquivo)
"dimensao: {0}x{1}" -f $medida.Width, $medida.Height
$medida.Dispose()
