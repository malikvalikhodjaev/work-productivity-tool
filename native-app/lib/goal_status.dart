import 'work_stage_board.dart';

const goalStatusOptions = {
  ...workStageLabels,
  'paused': 'На паузе',
  'archived': 'В архиве',
};

String goalStatusLabel(dynamic status) =>
    goalStatusOptions[status] ?? 'Заполнить';
