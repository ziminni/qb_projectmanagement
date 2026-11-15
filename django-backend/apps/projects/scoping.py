"""The one implementation of "which projects may this caller see?".

Every project-scoped queryset goes through `projects_for()`, mirroring
`repositories/mock_project_repository.dart:41-51`: company-wide roles see
everything, everyone else sees only projects with an **accepted** assignment in
their active role. Pending / `not_sent` / `changes_requested` / `declined`
assignments grant nothing (the invitee still sees the request through
`project-requests/`).

A declined project is hidden from every read (decision 06 R1) and never
serialized, so no Flutter enum ever has to parse it.
"""

from rest_framework.exceptions import NotFound

from ..users import capabilities
from ..users.models import Role
from .models import Project, ProjectStatus, RequestResponse, RoleOnProject
from .rules import NotAllowed


def projects_for(user, role):
    """Projects visible to `user` acting as `role` (declined ones excluded)."""
    queryset = Project.objects.exclude(status=ProjectStatus.DECLINED)
    if capabilities.sees_all_projects(role):
        return queryset
    return queryset.filter(
        assignments__user=user,
        assignments__role_on_project=role,
        assignments__response=RequestResponse.ACCEPTED,
    ).distinct()


def project_or_404(user, role, project_id):
    """The project when it is in the caller's scope, else `404`."""
    project = projects_for(user, role).filter(pk=project_id).first()
    if project is None:
        raise NotFound()
    return project


def has_accepted_assignment(project, user, role_on_project):
    """Whether `user` holds an accepted assignment in `role_on_project`."""
    return project.assignments.filter(
        user=user,
        role_on_project=role_on_project,
        response=RequestResponse.ACCEPTED,
    ).exists()


def require_owner(project, user, message):
    """403 unless `user` is an accepted `owner` of `project`."""
    if not has_accepted_assignment(project, user, RoleOnProject.OWNER):
        raise NotAllowed(message)


def require_owner_or_site_engineer(project, user, active_role, message):
    """403 unless `user` is an accepted owner, or an accepted SE in that role."""
    if active_role == RoleOnProject.OWNER:
        require_owner(project, user, message)
        return
    if active_role == RoleOnProject.SITE_ENGINEER and has_accepted_assignment(
        project, user, RoleOnProject.SITE_ENGINEER,
    ):
        return
    raise NotAllowed(message)


def require_staff(active_role, message):
    """403 for the client portal role (staff-only reads such as the team list)."""
    if active_role not in capabilities.STAFF_ROLES:
        raise NotAllowed(message)


def require_client_writer(active_role, message):
    """403 unless the active role may change a client record.

    Reads stay staff-wide (the project form picks `client_id`), but only the
    Owner/Project Manager and Admin roles may create, edit or link a client.
    The Accountant keeps read access only.
    """
    if active_role not in (Role.ADMIN, Role.OWNER):
        raise NotAllowed(message)
