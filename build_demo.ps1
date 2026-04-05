$ErrorActionPreference = "Stop"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " NeurISA MNIST Demo - Build Script"
Write-Host "============================================" -ForegroundColor Cyan

$ProjectRoot = "C:/Users/Anuj/ChipMonk"
$NEORV32_HOME = "$ProjectRoot/rtl/neorv32"
$BUILD = "$ProjectRoot/build_neurisa"
$INC = "$NEORV32_HOME/sw/lib/include"
$SRC_DIR = "$NEORV32_HOME/sw/lib/source"
$COMMON = "$NEORV32_HOME/sw/common"
$NEURISA_INC = "$ProjectRoot/sw/lib"
$OUTPUT_ELF = "$BUILD/neurisa_demo.elf"
$OUTPUT_BIN = "$ProjectRoot/neurisa_demo.bin"

# Architecture flags
$archFlag = "-march=rv32imac_zicsr_zifencei"
$abiFlag = "-mabi=ilp32"

# Create build directory
if (Test-Path $BUILD) { Remove-Item -Recurse -Force $BUILD }
New-Item -ItemType Directory -Force -Path $BUILD | Out-Null

# Gather all NEORV32 library sources
$neorv32_srcs = Get-ChildItem "$SRC_DIR/*.c" | ForEach-Object { $_.FullName }
Write-Host "Found $($neorv32_srcs.Count) NEORV32 library sources" -ForegroundColor Yellow

# App sources
$app_srcs = @(
    "$ProjectRoot/sw/app/selftest/main.c"
)

$all_c_srcs = $app_srcs + $neorv32_srcs

# Common compile args
$commonArgs = @($archFlag, $abiFlag, "-Os", "-Wall", "-ffunction-sections", "-fdata-sections", "-nostartfiles", "-mno-fdiv", "-mstrict-align", "-mbranch-cost=10", "-g", "-I", $INC, "-I", $NEURISA_INC)

# ============================================================
# Step 1: Compile all C sources
# ============================================================
Write-Host "[1/4] Compiling C sources..." -ForegroundColor Yellow
foreach ($src in $all_c_srcs) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($src)
    $obj = "$BUILD/${name}.o"
    Write-Host "  CC $name"
    $args = @("-c") + $commonArgs + @($src, "-o", $obj)
    & riscv-none-elf-gcc @args
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to compile $name" -ForegroundColor Red
        exit 1
    }
}

# ============================================================
# Step 2: Compile startup assembly
# ============================================================
Write-Host "[2/4] Compiling startup code..." -ForegroundColor Yellow
$asmArgs = @("-c", $archFlag, $abiFlag, "-Os", "-Wall", "-ffunction-sections", "-fdata-sections", "-nostartfiles", "-mno-fdiv", "-mstrict-align", "-g", "-I", $INC, "$COMMON/crt0.S", "-o", "$BUILD/crt0.o")
& riscv-none-elf-gcc @asmArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to compile crt0.S" -ForegroundColor Red
    exit 1
}
Write-Host "  AS crt0.S OK" -ForegroundColor Green

# ============================================================
# Step 3: Link
# ============================================================
Write-Host "[3/4] Linking..." -ForegroundColor Yellow
$objs = Get-ChildItem "$BUILD/*.o" | ForEach-Object { $_.FullName }
Write-Host "  Linking $($objs.Count) objects..."

$linkArgs = @($archFlag, $abiFlag, "-Os", "-Wall", "-ffunction-sections", "-fdata-sections", "-nostartfiles", "-mno-fdiv", "-mstrict-align", "-mbranch-cost=10", "-g", "-Wl,--gc-sections", "-T", "$COMMON/neorv32.ld") + $objs + @("-lm", "-lc", "-lgcc", "-o", $OUTPUT_ELF)
& riscv-none-elf-gcc @linkArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Linking failed" -ForegroundColor Red
    exit 1
}

Write-Host "  Memory utilization:" -ForegroundColor Green
& riscv-none-elf-size $OUTPUT_ELF

# ============================================================
# Step 4: Convert ELF to NEORV32 bootloader binary
# ============================================================
Write-Host "[4/4] Generating bootloader binary..." -ForegroundColor Yellow
& python "$ProjectRoot/sw/tools/image_gen.py" -i $OUTPUT_ELF -o $OUTPUT_BIN -t exe
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Image generation failed" -ForegroundColor Red
    exit 1
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " BUILD COMPLETE!" -ForegroundColor Green
Write-Host " Binary: $OUTPUT_BIN"
Write-Host " Upload: python upload_uart.py COM4 neurisa_demo.bin"
Write-Host "============================================" -ForegroundColor Cyan
