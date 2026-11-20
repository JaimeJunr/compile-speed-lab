# Object Pascal (Free Pascal): M units, cada uma compilada à parte e reaproveitada pelo .ppu.

pascal_gen() {
  local d=$1 m=$2 f=$3 i j uses=""
  mkdir -p "$d/units"
  for ((j = 0; j < m; j++)); do uses+="${uses:+, }m$j"; done
  {
    echo 'program main;'
    echo '{$mode objfpc}{$Q-}{$R-}'
    echo "uses $uses;"
    echo 'var acc: QWord;'
    echo 'begin'
    echo '  acc := 0;'
    for ((j = 0; j < m; j++)); do echo "  acc := acc + run$j(acc);"; done
    echo '  writeln(acc);'
    echo 'end.'
  } > "$d/main.pas"
  for ((j = 0; j < m; j++)); do
    {
      echo "unit m$j;"
      echo '{$mode objfpc}{$Q-}{$R-}'
      echo 'interface'
      echo "function run$j(x: QWord): QWord;"
      echo 'implementation'
      for ((i = 0; i < f; i++)); do
        echo "function f$i(x: QWord): QWord;"
        echo 'var a: QWord;'
        echo 'begin'
        echo "  a := x xor $((i * 7 + j));"
        echo "  a := a * QWord(6364136223846793005) + $i;"
        ((i == 0)) && echo "  a := a + 7; // EDIT"
        echo "  if a mod 3 = 0 then Result := a shr 1 else Result := a + $j;"
        echo 'end;'
      done
      echo "function run$j(x: QWord): QWord;"
      echo 'var a: QWord;'
      echo 'begin'
      echo '  a := x;'
      for ((i = 0; i < f; i++)); do echo "  a := f$i(a);"; done
      echo '  Result := a;'
      echo 'end;'
      echo 'end.'
    } > "$d/m$j.pas"
  done
}

pascal_clean() { rm -rf "$1/units"/* "$1/bin"; }
pascal_build() { (cd "$1" && fpc -v0 -O- -g -FUunits -obin main.pas >/dev/null); }
pascal_version() { echo "fpc $(fpc -iV)"; }
