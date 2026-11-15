"""Projects app admin: sites, clients, projects and the WBS."""

from django.contrib import admin

from .models import Category, Client, Project, ProjectAssignment, Site, Todo


class ProjectAssignmentInline(admin.TabularInline):
    model = ProjectAssignment
    extra = 0
    fields = ('user', 'role_on_project', 'response', 'note', 'responded_at')


class CategoryInline(admin.TabularInline):
    model = Category
    extra = 0
    fields = ('name', 'budget', 'sort_order')


@admin.register(Site)
class SiteAdmin(admin.ModelAdmin):
    list_display = ('code', 'name', 'city', 'province', 'status')
    list_filter = ('status', 'province')
    search_fields = ('code', 'name', 'city')


@admin.register(Client)
class ClientAdmin(admin.ModelAdmin):
    list_display = ('name', 'contact_person', 'email', 'phone', 'user')
    search_fields = ('name', 'contact_person', 'email')


@admin.register(Project)
class ProjectAdmin(admin.ModelAdmin):
    list_display = (
        'code', 'name', 'client', 'status', 'contract_amount',
        'start_date', 'target_end_date',
    )
    list_filter = ('status', 'client')
    search_fields = ('code', 'name', 'location')
    readonly_fields = ('created_at', 'updated_at')
    inlines = (ProjectAssignmentInline, CategoryInline)


@admin.register(ProjectAssignment)
class ProjectAssignmentAdmin(admin.ModelAdmin):
    list_display = ('project', 'user', 'role_on_project', 'response', 'responded_at')
    list_filter = ('role_on_project', 'response')
    search_fields = ('project__code', 'user__full_name', 'user__email')


@admin.register(Category)
class CategoryAdmin(admin.ModelAdmin):
    list_display = ('name', 'project', 'budget', 'sort_order')
    search_fields = ('name', 'project__code')


@admin.register(Todo)
class TodoAdmin(admin.ModelAdmin):
    list_display = (
        'title', 'category', 'start_date', 'end_date', 'is_done', 'is_verified',
    )
    list_filter = ('is_done', 'is_verified')
    search_fields = ('title', 'category__name', 'category__project__code')
