# TODO

## Lock Screen

- [x] Plugin UI system — `lockScreen` entry point, `LockScreenRegistry`, dynamic loading
- [ ] External locker support — swaylock/hyprlock integration (shell only orchestrates lock trigger)
- [ ] Custom auth — plugin provides its own LockContext/PAM, shell only wraps WlSessionLock

## Dialog System

- [x] CLI dialog scripts (alert, confirm, prompt, survey)
- [ ] Support keyboard navigation (Tab focus cycling in NButton/NTextInput)
