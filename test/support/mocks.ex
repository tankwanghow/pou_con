defmodule PouCon.TestMocks do
  Mox.defmock(PouCon.DeviceManagerMock, for: PouCon.Hardware.DeviceManagerBehaviour)
end
