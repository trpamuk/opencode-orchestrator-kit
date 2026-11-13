param(
  [switch]$SelfTest,
  [string]$ConfigDir = (Join-Path $env:USERPROFILE ".config\opencode")
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$kitRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$installer = Join-Path $kitRoot "install.ps1"

function Get-Catalog {
  try {
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -ListModels -ConfigDir $ConfigDir 2>&1
    $line = $output | Where-Object { $_ -match '^\s*\{' } | Select-Object -Last 1
    if (-not $line) { return $null }
    return $line | ConvertFrom-Json
  } catch {
    return $null
  }
}

$catalog = Get-Catalog

$form = New-Object System.Windows.Forms.Form
$form.Text = "OpenCode Orchestrator Kit"
$form.Size = New-Object System.Drawing.Size(680, 560)
$form.MinimumSize = New-Object System.Drawing.Size(560, 460)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 22)
$form.ForeColor = [System.Drawing.Color]::FromArgb(236, 236, 241)
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

$title = New-Object System.Windows.Forms.Label
$title.Text = "OpenCode Orchestrator Kit"
$title.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = [System.Drawing.Color]::FromArgb(240, 198, 116)
$title.Location = New-Object System.Drawing.Point(16, 12)
$title.Size = New-Object System.Drawing.Size(520, 30)
$form.Controls.Add($title)

$modelLabel = New-Object System.Windows.Forms.Label
$modelLabel.Text = "Model"
$modelLabel.Location = New-Object System.Drawing.Point(16, 58)
$modelLabel.Size = New-Object System.Drawing.Size(70, 22)
$form.Controls.Add($modelLabel)

$combo = New-Object System.Windows.Forms.ComboBox
$combo.Location = New-Object System.Drawing.Point(92, 56)
$combo.Size = New-Object System.Drawing.Size(550, 26)
$combo.DropDownStyle = "DropDown"
$combo.AutoCompleteMode = "SuggestAppend"
$combo.AutoCompleteSource = "ListItems"
$form.Controls.Add($combo)

$table = New-Object System.Data.DataTable
$table.Columns.Add("Display") | Out-Null
$table.Columns.Add("Id") | Out-Null
$items = @(
  @{ Display = "Mevcut modeli koru"; Id = "__keep" },
  @{ Display = "Model alanini bos birak (OpenCode'da sec)"; Id = "__none" }
)
foreach ($model in @($catalog.models)) {
  $text = "$($model.Id) - $($model.Name)"
  if ($model.Vision) { $text += " (vision)" }
  $items += @{ Display = $text; Id = $model.Id }
}
foreach ($item in $items) {
  $row = $table.NewRow()
  $row["Display"] = $item.Display
  $row["Id"] = $item.Id
  $table.Rows.Add($row)
}
$combo.DisplayMember = "Display"
$combo.ValueMember = "Id"
$combo.DataSource = $table
$combo.SelectedIndex = 0

$defaultLabel = New-Object System.Windows.Forms.Label
$defaultLabel.Location = New-Object System.Drawing.Point(92, 86)
$defaultLabel.Size = New-Object System.Drawing.Size(550, 20)
$defaultLabel.ForeColor = [System.Drawing.Color]::FromArgb(139, 139, 150)
$defaultLabel.Text = if ($catalog -and $catalog.default) { "Varsayilan model: $($catalog.default)" } else { "OpenCode servisi kapali veya varsayilan model yok. Model secimini OpenCode icinden yapabilirsin." }
$form.Controls.Add($defaultLabel)

$shortcuts = New-Object System.Windows.Forms.CheckBox
$shortcuts.Text = "Masaustu ve Startup kisayollarini olustur"
$shortcuts.Checked = $true
$shortcuts.Location = New-Object System.Drawing.Point(16, 116)
$shortcuts.Size = New-Object System.Drawing.Size(420, 24)
$form.Controls.Add($shortcuts)

$startPanel = New-Object System.Windows.Forms.CheckBox
$startPanel.Text = "Paneli kurulumdan sonra baslat"
$startPanel.Checked = $true
$startPanel.Location = New-Object System.Drawing.Point(16, 144)
$startPanel.Size = New-Object System.Drawing.Size(420, 24)
$form.Controls.Add($startPanel)

$installButton = New-Object System.Windows.Forms.Button
$installButton.Text = "Kur"
$installButton.Location = New-Object System.Drawing.Point(16, 180)
$installButton.Size = New-Object System.Drawing.Size(110, 34)
$installButton.BackColor = [System.Drawing.Color]::FromArgb(34, 197, 94)
$installButton.ForeColor = [System.Drawing.Color]::White
$installButton.FlatStyle = "Flat"
$form.Controls.Add($installButton)

$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = "Kapat"
$closeButton.Location = New-Object System.Drawing.Point(136, 180)
$closeButton.Size = New-Object System.Drawing.Size(90, 34)
$closeButton.FlatStyle = "Flat"
$form.Controls.Add($closeButton)

$log = New-Object System.Windows.Forms.TextBox
$log.Location = New-Object System.Drawing.Point(16, 228)
$log.Size = New-Object System.Drawing.Size(630, 280)
$log.Multiline = $true
$log.ReadOnly = $true
$log.ScrollBars = "Vertical"
$log.Font = New-Object System.Drawing.Font("Consolas", 9)
$log.BackColor = [System.Drawing.Color]::FromArgb(11, 11, 13)
$log.ForeColor = [System.Drawing.Color]::FromArgb(199, 199, 209)
$log.Anchor = "Top,Left,Right,Bottom"
$form.Controls.Add($log)

$closeButton.Add_Click({ $form.Close() })

$installButton.Add_Click({
  $modelId = [string]$combo.SelectedValue
  $installArgs = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $installer,
    "-ConfigDir", $ConfigDir
  )
  if (-not $shortcuts.Checked) { $installArgs += "-NoShortcuts" }
  if (-not $startPanel.Checked) { $installArgs += "-NoStart" }
  switch ($modelId) {
    "__keep" { $installArgs += "-NoModelPrompt" }
    "__none" { $installArgs += "-ClearModel" }
    default { $installArgs += @("-Model", $modelId) }
  }

  $installButton.Enabled = $false
  $closeButton.Enabled = $false
  $combo.Enabled = $false
  $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
  $log.Text = "Kurulum basliyor...`r`n"
  [System.Windows.Forms.Application]::DoEvents()

  try {
    $output = & powershell @installArgs 2>&1
    $log.Text = ($output -join "`r`n")
    [System.Windows.Forms.MessageBox]::Show(
      "Kurulum tamamlandi.`r`n`r`nOpenCode Desktop'i tamamen kapatip yeniden ac.",
      "Basarili",
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
  } catch {
    $log.Text += "`r`nHATA: $($_.Exception.Message)"
    [System.Windows.Forms.MessageBox]::Show(
      "Kurulum basarisiz.`r`n`r`n$($_.Exception.Message)",
      "Hata",
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
  } finally {
    $form.Cursor = [System.Windows.Forms.Cursors]::Default
    $installButton.Enabled = $true
    $closeButton.Enabled = $true
    $combo.Enabled = $true
  }
})

if ($SelfTest) {
  Write-Output ("selftest_ok form=" + $form.Text + " items=" + $combo.Items.Count + " selected=" + $combo.SelectedValue + " default=" + $defaultLabel.Text)
  $form.Dispose()
  exit 0
}

[void]$form.ShowDialog()
$form.Dispose()

