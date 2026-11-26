import MpvQml

// The image owner loads this component only on a video cache miss.
MpvFrameCapture {
  function admit(source, width, height, destination) {
    const attempt = tryCapture(source, 0.1, width, height, destination);
    switch (attempt.status) {
    case MpvFrameCapture.Accepted:
      return {
        id: attempt.id
      };
    case MpvFrameCapture.LocalBusy:
      return {
        waiting: true
      };
    case MpvFrameCapture.SharedBusy:
      return {
        waiting: true,
        shared: true
      };
    default:
      return {
        code: "video-backend-unavailable"
      };
    }
  }
}
