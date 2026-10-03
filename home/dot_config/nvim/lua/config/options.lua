-- 判斷是否為 SSH 連線
local is_ssh = os.getenv("SSH_CONNECTION") ~= nil

if is_ssh then
  -- 如果是 SSH，使用 OSC 52 (讓電腦/平板能接收剪貼簿)
  vim.g.clipboard = {
    name = 'OSC 52',
    copy = {
      ['+'] = require('vim.ui.clipboard.osc52').copy('+'),
      ['*'] = require('vim.ui.clipboard.osc52').copy('*'),
    },
    paste = {
      ['+'] = require('vim.ui.clipboard.osc52').paste('+'),
      ['*'] = require('vim.ui.clipboard.osc52').paste('*'),
    },
  }
elseif vim.fn.executable('termux-clipboard-set') == 1 then
  -- 如果是手機本機操作，使用 Termux 專用指令
  vim.g.clipboard = {
    name = 'termux-clipboard',
    copy = {
      ['+'] = 'termux-clipboard-set',
      ['*'] = 'termux-clipboard-set',
    },
    paste = {
      ['+'] = 'termux-clipboard-get',
      ['*'] = 'termux-clipboard-get',
    },
    cache_enabled = 0,
  }
end
-- 其他情況(WSL、桌面 Linux 本機)不設 vim.g.clipboard,讓 nvim 自己找可用的剪貼簿工具

-- 最後統一開啟同步功能
vim.opt.clipboard = "unnamedplus"
