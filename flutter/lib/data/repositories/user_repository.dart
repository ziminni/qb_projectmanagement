import '../models/app_role.dart';
import '../models/user.dart';
import '../models/user_role.dart';

abstract interface class UserRepository {
  Future<List<User>> getUsers();

  Future<User?> getUser(int id);

  Future<List<AppRole>> getRoles(int userId);

  Future<List<UserRole>> getAllUserRoles();

  /// Creates the user when [user] has id 0, otherwise updates it, and
  /// replaces their roles. A user needs at least one role and a unique email.
  Future<User> saveUser(User user, List<AppRole> roles);

  Future<User> setActive(int userId, bool active);

  /// Users holding [role], e.g. every PM for an assignment picker.
  Future<List<User>> getUsersWithRole(AppRole role);
}
