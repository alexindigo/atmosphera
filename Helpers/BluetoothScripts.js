.pragma library

var pairAndConnectScript = (addr, pairWaitSeconds, attempts, intervalSec) => {
  // Produces a shell script that pairs, trusts and attempts to connect repeatedly.
  return `
      addr='${addr}'
      {
        echo 'agent KeyboardDisplay'
        echo 'default-agent'
        echo 'power on'
        echo "pair $addr"
        # Give time for potential confirmation prompt; send 'yes' optimistically (no-op if not needed)
        sleep 1
        echo 'yes'
        # Mark device trusted
        echo "trust $addr"
        # Attempt multiple connects within the session
        for i in $(seq 1 ${attempts}); do
          echo "connect $addr"
          sleep ${intervalSec}
        done
        echo 'quit'
      } | bluetoothctl &

      # Wait up to ${pairWaitSeconds}s for pairing to complete
      for i in $(seq 1 ${pairWaitSeconds}); do
        if bluetoothctl info "$addr" | grep -q 'Paired: yes'; then
          break
        fi
        sleep 1
      done

      # Check connection state for ~${attempts * intervalSec}s total
      for i in $(seq 1 ${attempts}); do
        if bluetoothctl info "$addr" | grep -q 'Connected: yes'; then
          exit 0
        fi
        sleep ${intervalSec}
      done
      exit 1
    `;
};
