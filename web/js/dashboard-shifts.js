(function(root) {
  'use strict';
  root.countAssignedGuardShifts = function(docs, guardIds) {
    return docs.filter(record => {
      const shift = record.data();
      const status = shift.approval_status ?? shift.approvalStatus;
      return guardIds.has(shift.userId ?? shift.user_id) && !['draft','cancelled'].includes(status);
    }).length;
  };
})(window);
